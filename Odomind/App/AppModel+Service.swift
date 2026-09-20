import Foundation
import OdomindCore

/// What the "Log service" screen collects.
struct ServiceDraft {
    var vehicleID: UUID
    var performedOn: Date
    var odometerAmount: Int?
    /// Plan items ticked as completed.
    var selectedPlanItemIDs: Set<UUID> = []
    /// Catalog tasks completed that are not in the plan; added to history
    /// without being added to the schedule.
    var extraDefinitionIDs: Set<String> = []
    var totalCostText: String = ""
    var currencyCode: String
    var performer: ServicePerformer = .doItYourself
    var notes: String = ""
    var attachmentIDs: [UUID] = []
    /// Set when editing an existing record rather than creating one.
    var editingRecordID: UUID?

    var hasSelection: Bool { !selectedPlanItemIDs.isEmpty || !extraDefinitionIDs.isEmpty }
}

extension AppModel {

    /// Turns a draft into a record without saving it, so the screen can validate
    /// and show a total before anything is written.
    func buildServiceRecord(from draft: ServiceDraft) -> ServiceRecord? {
        guard let vehicle = snapshot.vehicle(id: draft.vehicleID) else { return nil }
        let catalog = catalogService.catalog

        var items: [ServiceLineItem] = []
        for planItemID in draft.selectedPlanItemIDs {
            guard let item = planItem(id: planItemID) else { continue }
            items.append(
                ServiceLineItem(
                    planItemID: item.id,
                    definitionID: item.definitionID,
                    title: item.title,
                    action: item.action
                )
            )
        }
        for definitionID in draft.extraDefinitionIDs {
            guard !items.contains(where: { $0.definitionID == definitionID }) else { continue }
            let definition = catalog?.definition(id: definitionID)
            items.append(
                ServiceLineItem(
                    definitionID: definitionID,
                    title: definition?.title ?? definitionID,
                    action: definition?.action ?? .replace
                )
            )
        }
        items.sort { $0.title.lowercased() < $1.title.lowercased() }

        // One total for the visit, not one per task. A receipt covering four
        // jobs is one charge.
        var totalCost: Money?
        let trimmedCost = draft.totalCostText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCost.isEmpty {
            guard let amount = Self.parseAmount(trimmedCost) else { return nil }
            totalCost = Money(amount: amount, currencyCode: draft.currencyCode)
        }

        let existing = draft.editingRecordID.flatMap { id in
            snapshot.serviceRecords.first { $0.id == id }
        }

        return ServiceRecord(
            id: existing?.id ?? UUID(),
            vehicleID: vehicle.id,
            performedOn: draft.performedOn,
            odometer: draft.odometerAmount.map { Distance($0, vehicle.displayUnit) },
            items: items,
            totalCost: totalCost,
            performer: draft.performer,
            notes: draft.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : draft.notes,
            attachmentIDs: draft.attachmentIDs,
            isDemo: existing?.isDemo ?? false,
            createdAt: existing?.createdAt ?? clock.now,
            updatedAt: clock.now
        )
    }

    /// Parses an amount the owner typed, accepting either decimal separator.
    ///
    /// Uses `Decimal` throughout so 89.97 stays 89.97.
    static func parseAmount(_ text: String) -> Decimal? {
        let cleaned = text
            .replacingOccurrences(of: ",", with: ".")
            .filter { $0.isNumber || $0 == "." || $0 == "-" }
        guard !cleaned.isEmpty, cleaned.filter({ $0 == "." }).count <= 1 else { return nil }
        return Decimal(string: cleaned)
    }

    func serviceIssues(for draft: ServiceDraft) -> [ServiceRecordIssue] {
        guard let vehicle = snapshot.vehicle(id: draft.vehicleID),
              let record = buildServiceRecord(from: draft) else { return [] }
        return ServiceRecordValidator.issues(
            for: record,
            ledger: ledger(for: vehicle),
            now: clock.now,
            calendar: calendar
        )
    }

    /// Saves a visit, and records the odometer reading that came with it.
    ///
    /// Logging service is the most common way an owner updates their mileage,
    /// so the reading is captured here rather than asking twice.
    @discardableResult
    func saveService(_ draft: ServiceDraft) -> UUID? {
        guard let record = buildServiceRecord(from: draft) else {
            alert = AppAlert(
                title: "Check the cost",
                message: "Odomind could not read the amount you entered. Use digits and a single decimal point."
            )
            return nil
        }

        let issues = serviceIssues(for: draft)
        if let blocking = issues.first(where: \.isBlocking) {
            alert = AppAlert(title: "Check this service", message: blocking.message)
            return nil
        }

        do {
            try store.save(serviceRecord: record)

            if let odometer = record.odometer {
                // The reading a visit produces carries the record's own
                // identifier. Editing the visit's odometer then updates that one
                // reading instead of leaving the old value behind, and deleting
                // the visit takes its reading with it.
                let coveredByAnotherReading = snapshot.readings(for: record.vehicleID).contains {
                    $0.id != record.id
                        && $0.value == odometer
                        && calendar.isDate($0.recordedOn, inSameDayAs: record.performedOn)
                }
                if coveredByAnotherReading {
                    try store.deleteReading(id: record.id)
                } else {
                    try store.save(
                        reading: OdometerReading(
                            id: record.id,
                            vehicleID: record.vehicleID,
                            recordedOn: record.performedOn,
                            value: odometer,
                            source: .serviceRecord
                        )
                    )
                }
            } else {
                try store.deleteReading(id: record.id)
            }
        } catch {
            alert = .saveFailed(error)
            return nil
        }

        refresh()
        Task { await syncReminders() }
        return record.id
    }

    func deleteService(id: UUID) async {
        var orphaned: [UUID] = []
        do {
            orphaned = try store.deleteServiceRecord(id: id)
            // The reading this visit contributed shares its identifier.
            try store.deleteReading(id: id)
        } catch {
            alert = .saveFailed(error)
            return
        }
        for attachmentID in orphaned {
            if let metadata = snapshot.attachment(id: attachmentID) {
                attachments.delete(fileName: metadata.fileName)
            }
        }
        refresh()
        sweepOrphanedAttachments()
        await syncReminders()
    }

    // MARK: - Attachments on a service record

    /// Stores a picked photo or file and registers it.
    ///
    /// Images are downscaled first: the backup format carries attachments
    /// inside it, and a full-resolution photo of a receipt helps nobody.
    @discardableResult
    func addAttachment(data: Data, contentType: String, caption: String? = nil) -> UUID? {
        let prepared = ImageProcessing.prepare(data: data, contentType: contentType)
        do {
            let metadata = try attachments.store(
                data: prepared.data,
                contentType: prepared.contentType,
                caption: caption
            )
            try store.registerAttachment(metadata)
            refresh()
            return metadata.id
        } catch {
            alert = AppAlert(
                title: "Could not save that file",
                message: String(describing: error),
                recoverySuggestion: "Check that your device has free space and try again."
            )
            return nil
        }
    }

    func removeAttachment(id: UUID, fromRecord recordID: UUID?) {
        do {
            if let recordID, var record = snapshot.serviceRecords.first(where: { $0.id == recordID }) {
                record.attachmentIDs.removeAll { $0 == id }
                record.updatedAt = clock.now
                try store.save(serviceRecord: record)
            }
            if let metadata = snapshot.attachment(id: id) {
                attachments.delete(fileName: metadata.fileName)
            }
            try store.deleteAttachment(id: id)
        } catch {
            alert = .saveFailed(error)
            return
        }
        refresh()
    }

    // MARK: - History reads

    func serviceRecords(for vehicleID: UUID, includingDemo: Bool = true) -> [ServiceRecord] {
        snapshot.serviceRecords(for: vehicleID)
            .filter { includingDemo || !$0.isDemo }
            .sorted { $0.performedOn > $1.performedOn }
    }

    /// Spending for a set of records, keeping currencies separate.
    func spending(for records: [ServiceRecord]) -> MoneyTotal {
        MoneyTotal.total(of: records.compactMap(\.totalCost))
    }
}
