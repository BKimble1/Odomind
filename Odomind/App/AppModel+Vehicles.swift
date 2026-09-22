import Foundation
import OdomindCore

/// Everything onboarding collects before a vehicle exists.
///
/// Held as one value so the flow can be resumed, cancelled or previewed without
/// half-created records appearing in the garage.
struct VehicleDraft {
    var nickname: String = ""
    var identity = VehicleIdentity(make: "", model: "")
    var configuration = VehicleConfiguration()
    var displayUnit: DistanceUnit = .miles
    var odometerAmount: Int?
    var odometerDate: Date = Date()
    var inServiceOn: Date?
    var acquiredOn: Date?
    var declaredTypicalDistancePerMonth: Distance?
    /// Catalog task ids the owner chose to track.
    var selectedTaskIDs: Set<String> = []
    /// What the owner said about each task's history. Anything absent is
    /// `.notProvided`, which the app treats as "still to be answered", never as
    /// "just serviced".
    var baselines: [String: HistoryBaseline] = [:]
    /// Set when the identity came from a VIN decode, so the confirm screen can
    /// show what the decoder actually said.
    var decodeResult: VehicleDecodeResult?

    var isReadyToSave: Bool {
        !identity.make.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !identity.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

extension AppModel {

    // MARK: - Vehicles

    /// Creates a vehicle, its first reading and its starting maintenance plan.
    ///
    /// Written in one pass so a failure part-way leaves nothing behind, and so
    /// the owner lands on a Today screen that already has something useful on it.
    @discardableResult
    func addVehicle(from draft: VehicleDraft) -> UUID? {
        guard draft.isReadyToSave else {
            alert = AppAlert(
                title: "Not enough to go on",
                message: "Odomind needs at least a make and a model to add this vehicle."
            )
            return nil
        }

        let now = clock.now
        let vehicle = Vehicle(
            nickname: draft.nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : draft.nickname.trimmingCharacters(in: .whitespacesAndNewlines),
            identity: draft.identity,
            configuration: draft.configuration,
            displayUnit: draft.displayUnit,
            acquiredOn: draft.acquiredOn,
            inServiceOn: draft.inServiceOn,
            createdAt: now,
            sortIndex: snapshot.vehicles.count
        )

        do {
            try store.save(vehicle: vehicle, declaredTypicalDistance: draft.declaredTypicalDistancePerMonth)

            if let amount = draft.odometerAmount {
                try store.save(
                    reading: OdometerReading(
                        vehicleID: vehicle.id,
                        recordedOn: draft.odometerDate,
                        value: Distance(amount, draft.displayUnit),
                        source: .initialSetup
                    )
                )
            }

            let items = makePlanItems(for: vehicle, draft: draft, now: now)
            if !items.isEmpty {
                try store.save(planItems: items)
            }

            var settings = snapshot.settings
            settings.selectedVehicleID = vehicle.id
            settings.hasCompletedOnboarding = true
            settings.catalogVersionLastSeen = catalogService.catalog?.catalogVersion
            try store.save(settings: settings)
        } catch {
            alert = .saveFailed(error)
            return nil
        }

        refresh()
        Task { await syncReminders() }
        return vehicle.id
    }

    private func makePlanItems(for vehicle: Vehicle, draft: VehicleDraft, now: Date) -> [MaintenancePlanItem] {
        guard let catalog = catalogService.catalog else { return [] }
        let suggestions = PlanBuilder.suggestions(for: vehicle, catalog: catalog)
        return suggestions
            .filter { draft.selectedTaskIDs.contains($0.definition.id) }
            .map { suggestion in
                PlanBuilder.makePlanItem(
                    from: suggestion,
                    vehicle: vehicle,
                    baseline: draft.baselines[suggestion.definition.id] ?? .notProvided,
                    createdAt: now
                )
            }
    }

    /// Sets, replaces or clears a vehicle's photo.
    ///
    /// Replacing one releases the file the old photo used, on the same rule
    /// the store applies elsewhere: an attachment goes only when nothing else
    /// points at it. A restored backup can legitimately share one image
    /// between a vehicle and a receipt, and deleting the file out from under
    /// the receipt would turn a cosmetic change into lost evidence.
    func setPhoto(_ attachmentID: UUID?, for vehicle: Vehicle) {
        let previous = vehicle.photoAttachmentID
        guard previous != attachmentID else { return }

        var updated = vehicle
        updated.photoAttachmentID = attachmentID
        updateVehicle(updated)

        // After the save, so the snapshot this reads already has the new
        // photo in it and cannot see the old one as still referenced.
        if let previous { releaseAttachmentIfUnreferenced(previous) }
    }

    private func releaseAttachmentIfUnreferenced(_ id: UUID) {
        let inUse = snapshot.serviceRecords.contains { $0.attachmentIDs.contains(id) }
            || snapshot.vehicles.contains { $0.photoAttachmentID == id }
        guard !inUse else { return }
        removeAttachment(id: id, fromRecord: nil)
    }

    func updateVehicle(_ vehicle: Vehicle, declaredTypicalDistance: Distance? = nil) {
        do {
            try store.save(vehicle: vehicle, declaredTypicalDistance: declaredTypicalDistance)
        } catch {
            alert = .saveFailed(error)
            return
        }
        refresh()
        Task { await syncReminders() }
    }

    /// Deletes a vehicle, its history, its files and its reminders.
    func deleteVehicle(id: UUID) async {
        let planItemIDs = snapshot.planItems(for: id).map(\.id)

        // The store decides which attachments are genuinely orphaned; one that
        // another vehicle's record still references must keep its file.
        let orphaned: [UUID]
        do {
            orphaned = try store.deleteVehicle(id: id)
        } catch {
            alert = .saveFailed(error)
            return
        }

        for attachmentID in orphaned {
            if let metadata = snapshot.attachment(id: attachmentID) {
                attachments.delete(fileName: metadata.fileName)
            }
        }
        await reminderCoordinator.cancelReminders(forPlanItemIDs: planItemIDs)
        await reminderCoordinator.cancelMileageReminder(vehicleID: id)

        refresh()
        sweepOrphanedAttachments()
        await syncReminders()
    }

    // MARK: - Odometer

    /// Validates a proposed reading without saving it, so the entry screen can
    /// explain a problem before the owner commits to it.
    func odometerIssues(
        for vehicle: Vehicle,
        proposedAmount: Int,
        on date: Date,
        excluding existingID: UUID? = nil
    ) -> [OdometerIssue] {
        ledger(for: vehicle).issues(
            forProposed: Distance(proposedAmount, vehicle.displayUnit),
            on: date,
            now: clock.now,
            calendar: calendar,
            excluding: existingID
        )
    }

    @discardableResult
    func recordOdometer(
        vehicleID: UUID,
        amount: Int,
        on date: Date? = nil,
        note: String? = nil,
        source: OdometerSource = .manualEntry
    ) -> Bool {
        guard let vehicle = snapshot.vehicle(id: vehicleID) else { return false }
        let reading = OdometerReading(
            vehicleID: vehicleID,
            recordedOn: date ?? clock.now,
            value: Distance(amount, vehicle.displayUnit),
            source: source,
            note: note
        )
        do {
            try store.save(reading: reading)
        } catch {
            alert = .saveFailed(error)
            return false
        }
        refresh()
        Task { await syncReminders() }
        return true
    }

    func updateReading(_ reading: OdometerReading) {
        do {
            try store.save(reading: reading)
        } catch {
            alert = .saveFailed(error)
            return
        }
        refresh()
        Task { await syncReminders() }
    }

    func deleteReading(id: UUID) {
        do {
            try store.deleteReading(id: id)
        } catch {
            alert = .saveFailed(error)
            return
        }
        refresh()
        Task { await syncReminders() }
    }

    /// Records that the instrument cluster was replaced.
    ///
    /// This is the only way a decreasing odometer is accepted. Ordinary typos
    /// stay typos and are corrected, not reinterpreted as a new unit.
    func recordOdometerReplacement(
        vehicleID: UUID,
        occurredOn: Date,
        previousFinalReading: Int,
        newStartReading: Int,
        note: String?
    ) {
        guard var vehicle = snapshot.vehicle(id: vehicleID) else { return }
        vehicle.odometerReplacements.append(
            OdometerReplacement(
                occurredOn: occurredOn,
                previousUnitFinalReading: Distance(previousFinalReading, vehicle.displayUnit),
                replacementUnitStartReading: Distance(newStartReading, vehicle.displayUnit),
                note: note
            )
        )
        vehicle.odometerReplacements.sort { $0.occurredOn < $1.occurredOn }
        updateVehicle(vehicle)
    }

    func removeOdometerReplacement(vehicleID: UUID, replacementID: UUID) {
        guard var vehicle = snapshot.vehicle(id: vehicleID) else { return }
        vehicle.odometerReplacements.removeAll { $0.id == replacementID }
        updateVehicle(vehicle)
    }

    func setDeclaredTypicalDistance(vehicleID: UUID, distance: Distance?) {
        guard let vehicle = snapshot.vehicle(id: vehicleID) else { return }
        updateVehicle(vehicle, declaredTypicalDistance: distance)
    }

    // MARK: - Specifications

    func saveSpecification(_ specification: Specification, for vehicleID: UUID) {
        var copy = specification
        copy.updatedAt = clock.now
        do {
            try store.save(specification: copy, for: vehicleID)
        } catch {
            alert = .saveFailed(error)
            return
        }
        refresh()
    }

    func deleteSpecification(kind: SpecificationKind, for vehicleID: UUID) {
        do {
            try store.deleteSpecification(kind: kind, for: vehicleID)
        } catch {
            alert = .saveFailed(error)
            return
        }
        refresh()
    }

    /// Specifications for a vehicle, merging the owner's entries over anything
    /// the catalog publishes.
    func resolvedSpecifications(for vehicle: Vehicle) -> [ResolvedSpecification] {
        guard let catalog = catalogService.catalog else { return [] }
        return PlanBuilder.resolvedSpecifications(
            vehicle: vehicle,
            catalog: catalog,
            ownerEntries: snapshot.specifications(for: vehicle.id)
        )
    }

    // MARK: - Sample content

    /// Adds the fictional sample vehicle, so someone can see how Odomind works
    /// before committing their own records to it.
    func addDemoContent() {
        guard let catalog = catalogService.catalog, let demo = catalog.demoContent else { return }
        guard !snapshot.vehicles.contains(where: \.isDemo) else { return }

        let now = clock.now
        let vehicle = Vehicle(
            nickname: demo.vehicleNickname,
            identity: demo.identity,
            configuration: demo.configuration,
            displayUnit: demo.displayUnit,
            inServiceOn: demo.inServiceOn,
            isDemo: true,
            createdAt: now,
            sortIndex: snapshot.vehicles.count
        )

        do {
            try store.save(vehicle: vehicle)

            for reading in demo.readings {
                guard let date = calendar.date(byAdding: .day, value: -reading.daysAgo, to: now) else { continue }
                try store.save(
                    reading: OdometerReading(
                        vehicleID: vehicle.id,
                        recordedOn: date,
                        value: Distance(reading.value, demo.displayUnit),
                        source: .manualEntry,
                        note: "Sample data"
                    )
                )
            }

            let suggestions = PlanBuilder.suggestions(for: vehicle, catalog: catalog, includeAdvanced: false)
            let items = suggestions
                .filter(\.isRecommendedByDefault)
                .map { PlanBuilder.makePlanItem(from: $0, vehicle: vehicle, createdAt: now) }
            try store.save(planItems: items)

            let itemsByDefinition = Dictionary(items.map { ($0.definitionID, $0) }, uniquingKeysWith: { first, _ in first })

            for service in demo.services {
                guard let date = calendar.date(byAdding: .day, value: -service.daysAgo, to: now) else { continue }
                let lineItems = service.definitionIDs.map { definitionID -> ServiceLineItem in
                    let definition = catalog.definition(id: definitionID)
                    return ServiceLineItem(
                        planItemID: itemsByDefinition[definitionID]?.id,
                        definitionID: definitionID,
                        title: definition?.title ?? definitionID,
                        action: definition?.action ?? .replace
                    )
                }
                var cost: Money?
                if let minorUnits = service.totalCostMinorUnits, let currency = service.currencyCode {
                    cost = Money(amount: Decimal(minorUnits) / 100, currencyCode: currency)
                }
                try store.save(
                    serviceRecord: ServiceRecord(
                        vehicleID: vehicle.id,
                        performedOn: date,
                        odometer: Distance(service.odometer, demo.displayUnit),
                        items: lineItems,
                        totalCost: cost,
                        performer: service.shopName.map { ServicePerformer.shop(name: $0) } ?? .doItYourself,
                        notes: service.notes,
                        isDemo: true,
                        createdAt: now,
                        updatedAt: now
                    )
                )
            }

            var settings = snapshot.settings
            if settings.selectedVehicleID == nil { settings.selectedVehicleID = vehicle.id }
            try store.save(settings: settings)
        } catch {
            alert = .saveFailed(error)
            return
        }

        refresh()
    }

    /// Removes the sample vehicle. Never touches the owner's own records.
    func removeDemoContent() async {
        guard let demoVehicle = snapshot.vehicles.first(where: \.isDemo) else { return }
        await deleteVehicle(id: demoVehicle.id)
    }

    var hasDemoContent: Bool { snapshot.vehicles.contains(where: \.isDemo) }

    var demoDisclaimer: String? { catalogService.catalog?.demoContent?.disclaimer }
}

// MARK: - Which vehicle the dashboard is about

extension AppModel {
    /// The vehicle the dashboard opens on.
    ///
    /// One vehicle means there is nothing to choose, so it shows that one and
    /// the switcher does not appear at all. Several means the pinned one, and
    /// failing that whichever is selected. Build 3 made this a control the
    /// owner had to operate on every screen; most people have one car.
    var dashboardVehicle: Vehicle? {
        // One car, counting the sample: nothing to choose, and no switcher.
        if snapshot.vehicles.count == 1 { return snapshot.vehicles.first }
        if let id = preferences.pinnedVehicleID, let pinned = snapshot.vehicle(id: id) {
            return pinned
        }
        return selectedVehicle
    }

    /// Whether the owner ever needs to be offered a choice of vehicle.
    var hasVehicleChoice: Bool { snapshot.vehicles.count > 1 }

    func isPinned(_ vehicle: Vehicle) -> Bool {
        preferences.pinnedVehicleID == vehicle.id
    }

    /// Pins a vehicle to the dashboard, or unpins it if it was already pinned.
    ///
    /// Pinning also selects, because they mean the same thing: this is the car
    /// the app is about. Keeping them apart let the dashboard sit on one car
    /// while Jobs sat on another, with nothing on either screen to explain it.
    func togglePin(_ vehicle: Vehicle) {
        let id = vehicle.id
        let wasPinned = preferences.pinnedVehicleID == id
        updatePreferences { preferences in
            preferences.pinnedVehicleID = wasPinned ? nil : id
        }
        if !wasPinned { selectVehicle(id) }
    }

    /// Switches every screen to a vehicle.
    ///
    /// The switcher used to set the selection only, so with a car pinned the
    /// dashboard ignored the pick. A pick is the owner saying which car they
    /// are looking at, so the pin moves with it rather than overruling it.
    func showVehicle(_ id: UUID) {
        selectVehicle(id)
        if preferences.pinnedVehicleID != nil, preferences.pinnedVehicleID != id {
            updatePreferences { $0.pinnedVehicleID = id }
        }
    }

    /// Records what the owner said they want to keep an eye on.
    ///
    /// Choosing nothing is recorded as an answer, not as a gap, so the
    /// question is put once and never again.
    func setTrackingInterests(_ interests: Set<TrackingInterest>) {
        updatePreferences {
            $0.trackingInterests = interests
            $0.hasAnsweredTrackingQuestion = true
        }
    }

    /// The jobs a new vehicle starts out tracking.
    ///
    /// The catalog's recommended set, narrowed to what the owner said they
    /// care about on first run. Until Build 4 the first-run answer was stored
    /// and never read, so somebody who said "tyres and brakes" still got
    /// eighteen ticked jobs — which is the screen the question was added to
    /// avoid.
    ///
    /// Narrowing only changes what starts out ticked. Everything the catalog
    /// offers this vehicle stays on the screen and one tap adds it back, so a
    /// wrong answer costs a tap rather than hiding work.
    func recommendedTaskIDs(from suggestions: [SuggestedTask]) -> Set<String> {
        let recommended = suggestions.filter(\.isRecommendedByDefault)
        let categories = preferences.trackingInterests.categories
        guard !categories.isEmpty else { return Set(recommended.map(\.definition.id)) }

        let narrowed = recommended.filter { categories.contains($0.definition.category) }
        // An answer that rules out everything this vehicle is offered is not a
        // usable answer. An empty starting plan reads as "Odomind found
        // nothing to track", which is worse than too much.
        guard !narrowed.isEmpty else { return Set(recommended.map(\.definition.id)) }
        return Set(narrowed.map(\.definition.id))
    }
}
