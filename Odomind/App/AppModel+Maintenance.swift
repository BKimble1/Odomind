import Foundation
import OdomindCore

extension AppModel {

    // MARK: - Adding and removing tasks

    /// Tasks the catalog can offer this vehicle that are not already tracked.
    func availableSuggestions(for vehicle: Vehicle, includeAdvanced: Bool = true) -> [SuggestedTask] {
        guard let catalog = catalogService.catalog else { return [] }
        let tracked = Set(snapshot.planItems(for: vehicle.id).map(\.definitionID))
        return PlanBuilder
            .suggestions(for: vehicle, catalog: catalog, includeAdvanced: includeAdvanced)
            .filter { !tracked.contains($0.definition.id) }
    }

    func allSuggestions(for vehicle: Vehicle) -> [SuggestedTask] {
        guard let catalog = catalogService.catalog else { return [] }
        return PlanBuilder.suggestions(for: vehicle, catalog: catalog, includeAdvanced: true)
    }

    @discardableResult
    func addTask(
        _ suggestion: SuggestedTask,
        to vehicle: Vehicle,
        baseline: HistoryBaseline = .notProvided
    ) -> UUID? {
        let item = PlanBuilder.makePlanItem(
            from: suggestion,
            vehicle: vehicle,
            baseline: baseline,
            createdAt: clock.now
        )
        do {
            try store.save(planItem: item)
        } catch {
            alert = .saveFailed(error)
            return nil
        }
        refresh()
        Task { await syncReminders() }
        return item.id
    }

    /// Adds a task the owner defined themselves.
    ///
    /// A custom task is never touched by a catalog update, and its identifier is
    /// namespaced so it can never collide with a published one.
    @discardableResult
    func addCustomTask(
        to vehicle: Vehicle,
        title: String,
        purpose: String,
        category: MaintenanceCategory,
        action: ServiceAction,
        rule: ScheduleRule?,
        baseline: HistoryBaseline = .notProvided
    ) -> UUID? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            alert = AppAlert(title: "Name this task", message: "A custom task needs a name.")
            return nil
        }
        if let rule {
            let problems = rule.validationProblems
            if !problems.isEmpty {
                alert = AppAlert(title: "Check the schedule", message: problems.joined(separator: "\n"))
                return nil
            }
        }

        let item = MaintenancePlanItem(
            vehicleID: vehicle.id,
            definitionID: "custom.\(UUID().uuidString)",
            title: trimmed,
            purpose: purpose,
            category: category,
            action: action,
            ownerRule: rule,
            baseline: baseline,
            dueSoonThreshold: PlanBuilder.defaultThreshold(for: vehicle),
            isCustom: true,
            createdAt: clock.now
        )
        do {
            try store.save(planItem: item)
        } catch {
            alert = .saveFailed(error)
            return nil
        }
        refresh()
        Task { await syncReminders() }
        return item.id
    }

    func removeTask(id: UUID) async {
        do {
            try store.deletePlanItem(id: id)
        } catch {
            alert = .saveFailed(error)
            return
        }
        await reminderCoordinator.cancelReminders(forPlanItemIDs: [id])
        refresh()
        await syncReminders()
    }

    // MARK: - Editing a task

    /// Applies a change and re-runs the schedule and reminders.
    private func mutate(planItemID: UUID, _ change: (inout MaintenancePlanItem) -> Void) {
        guard var item = planItem(id: planItemID) else { return }
        change(&item)
        do {
            try store.save(planItem: item)
        } catch {
            alert = .saveFailed(error)
            return
        }
        refresh()
        Task { await syncReminders() }
    }

    func setTaskEnabled(_ enabled: Bool, planItemID: UUID) {
        mutate(planItemID: planItemID) { $0.isEnabled = enabled }
    }

    /// Replaces the schedule with the owner's own.
    ///
    /// Stored separately from the catalog's rule, so a future catalog update
    /// cannot overwrite it and the owner can always go back to the published one.
    func setOwnerRule(_ rule: ScheduleRule, planItemID: UUID) {
        let problems = rule.validationProblems
        guard problems.isEmpty else {
            alert = AppAlert(title: "Check the schedule", message: problems.joined(separator: "\n"))
            return
        }
        mutate(planItemID: planItemID) { $0.ownerRule = rule }
    }

    func clearOwnerRule(planItemID: UUID) {
        mutate(planItemID: planItemID) { $0.ownerRule = nil }
    }

    func setDueSoonThreshold(_ threshold: DueSoonThreshold, planItemID: UUID) {
        mutate(planItemID: planItemID) { $0.dueSoonThreshold = threshold }
    }

    func setNotes(_ notes: String?, planItemID: UUID) {
        mutate(planItemID: planItemID) { $0.notes = notes }
    }

    /// Pauses reminders without changing the due date.
    ///
    /// Overdue work stays overdue on screen; only the notification moves.
    func snooze(planItemID: UUID, until date: Date) {
        mutate(planItemID: planItemID) { $0.snoozedUntil = date }
    }

    func snooze(planItemID: UUID, byDays days: Int) {
        guard let until = calendar.date(byAdding: .day, value: days, to: clock.now) else { return }
        snooze(planItemID: planItemID, until: until)
    }

    func cancelSnooze(planItemID: UUID) {
        mutate(planItemID: planItemID) { $0.snoozedUntil = nil }
    }

    func setReminder(_ preference: ReminderPreference, planItemID: UUID) {
        mutate(planItemID: planItemID) { $0.reminder = preference }
    }

    // MARK: - History baselines

    func setBaseline(_ baseline: HistoryBaseline, planItemID: UUID) {
        mutate(planItemID: planItemID) { $0.baseline = baseline }
    }

    /// "I don't know when this was last done, start counting from today."
    ///
    /// Recorded as a declared starting point rather than a fake service record,
    /// so the history stays honest: nothing claims work was done that was not.
    func startTrackingFromToday(planItemID: UUID) {
        guard let item = planItem(id: planItemID),
              let vehicle = snapshot.vehicle(id: item.vehicleID) else { return }
        let reading = latestReading(for: vehicle.id)
        mutate(planItemID: planItemID) {
            $0.baseline = .declared(date: clock.now, odometer: reading?.value)
        }
    }

    // MARK: - Catalog change proposals

    func acceptProposal(planItemID: UUID) {
        mutate(planItemID: planItemID) { $0.acceptPendingProposal() }
    }

    func dismissProposal(planItemID: UUID) {
        mutate(planItemID: planItemID) { $0.dismissPendingProposal() }
    }

    var pendingProposals: [MaintenancePlanItem] {
        snapshot.planItems.filter(\.hasPendingProposal)
    }

    /// Reconciles every vehicle's plan against the current catalog.
    ///
    /// Runs when the bundled catalog version changes — that is, when the owner
    /// installs a new build. Changed schedules are parked as proposals; nothing
    /// active moves until the owner accepts it.
    @discardableResult
    func applyCatalogUpdateIfNeeded() -> [CatalogChange] {
        guard let catalog = catalogService.catalog else { return [] }
        guard snapshot.settings.catalogVersionLastSeen != catalog.catalogVersion else { return [] }

        var allChanges: [CatalogChange] = []
        do {
            for vehicle in snapshot.vehicles where !vehicle.isDemo {
                let result = PlanBuilder.applyCatalogUpdate(
                    to: snapshot.planItems(for: vehicle.id),
                    vehicle: vehicle,
                    catalog: catalog,
                    now: clock.now
                )
                if !result.items.isEmpty {
                    try store.save(planItems: result.items)
                }
                allChanges.append(contentsOf: result.changes)
            }

            var settings = snapshot.settings
            settings.catalogVersionLastSeen = catalog.catalogVersion
            try store.save(settings: settings)
        } catch {
            alert = .saveFailed(error)
            return []
        }

        refresh()
        return allChanges
    }

    // MARK: - Calendar export

    /// Records that a calendar event was created, and for which due date.
    ///
    /// Odomind cannot update or remove that event afterwards, so it remembers
    /// what was written in order to warn about duplicates and to say plainly
    /// when the schedule has moved since.
    func markCalendarExported(planItemID: UUID, dueDate: Date?) {
        mutate(planItemID: planItemID) {
            $0.lastCalendarExportOn = clock.now
            $0.lastCalendarExportDueDate = dueDate
        }
    }

    func calendarExportState(planItemID: UUID) -> CalendarExportState {
        guard let item = planItem(id: planItemID) else { return .notExported }
        let evaluation = evaluation(planItemID: planItemID)
        return item.calendarExportState(currentDueDate: evaluation?.nextDueDate ?? evaluation?.estimatedDueDate)
    }
}
