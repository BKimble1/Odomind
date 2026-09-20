import SwiftUI
import EventKitUI
import OdomindCore

struct TaskDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let planItemID: UUID

    @State private var showingScheduleEditor = false
    @State private var showingServiceLog = false
    @State private var showingSnoozeOptions = false
    @State private var showingCalendarEditor = false
    @State private var showingDeleteConfirmation = false
    @State private var showingDuplicateCalendarWarning = false
    @State private var calendarEvent: CalendarEventDraft?

    private var item: MaintenancePlanItem? { model.planItem(id: planItemID) }
    private var evaluation: ScheduleEvaluation? { model.evaluation(planItemID: planItemID) }
    private var vehicle: Vehicle? { item.flatMap { model.snapshot.vehicle(id: $0.vehicleID) } }

    var body: some View {
        Group {
            if let item, let evaluation, let vehicle {
                content(item: item, evaluation: evaluation, vehicle: vehicle)
            } else {
                ContentUnavailableView(
                    "Task not found",
                    systemImage: "questionmark.folder",
                    description: Text("This task may have been removed.")
                )
            }
        }
        .navigationTitle(item?.title ?? "Task")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func content(item: MaintenancePlanItem, evaluation: ScheduleEvaluation, vehicle: Vehicle) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                    HStack {
                        DueBadge(state: evaluation.state)
                        Spacer()
                        Text(DueSummary.basisText(for: evaluation))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(DueSummary.text(for: evaluation, calendar: model.calendar, now: model.clock.now))
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, Theme.Spacing.tight)

                ForEach(Array(evaluation.reasons.enumerated()), id: \.offset) { _, reason in
                    InlineNotice(kind: noticeKind(for: reason), message: reason.message)
                }
            } header: {
                Text("Status")
            }

            if !item.purpose.isEmpty {
                Section("What this is for") {
                    Text(item.purpose)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let safetyNote = item.safetyNote {
                Section {
                    InlineNotice(kind: .safety, message: safetyNote)
                }
            }

            scheduleSection(item: item, evaluation: evaluation)
            dueSection(evaluation: evaluation, vehicle: vehicle)
            historySection(item: item, vehicle: vehicle)
            specificationsSection(item: item, vehicle: vehicle)
            actionsSection(item: item, evaluation: evaluation, vehicle: vehicle)
            reminderSection(item: item)
            manageSection(item: item)
        }
        .listStyle(.insetGrouped)
        .sheet(isPresented: $showingScheduleEditor) {
            ScheduleEditor(planItemID: planItemID)
        }
        .sheet(isPresented: $showingServiceLog) {
            LogServiceView(vehicle: vehicle, preselectedPlanItemID: planItemID)
        }
        .sheet(item: $calendarEvent) { draft in
            EventEditView(event: draft.event) { action in
                calendarEvent = nil
                if action == .saved {
                    model.markCalendarExported(
                        planItemID: planItemID,
                        dueDate: evaluation.nextDueDate ?? evaluation.estimatedDueDate
                    )
                }
            }
        }
        .confirmationDialog("Snooze reminders", isPresented: $showingSnoozeOptions, titleVisibility: .visible) {
            Button("For 1 week") { model.snooze(planItemID: planItemID, byDays: 7) }
            Button("For 1 month") { model.snooze(planItemID: planItemID, byDays: 30) }
            Button("For 3 months") { model.snooze(planItemID: planItemID, byDays: 90) }
            if item.snoozedUntil != nil {
                Button("Stop snoozing", role: .destructive) { model.cancelSnooze(planItemID: planItemID) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Snoozing pauses reminders. The due date does not change, and overdue work stays overdue.")
        }
        .alert("Add a second event?", isPresented: $showingDuplicateCalendarWarning) {
            Button("Add anyway") { presentCalendarEditor(evaluation: evaluation, vehicle: vehicle, item: item) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(duplicateCalendarMessage(item: item))
        }
        .confirmationDialog("Remove this task?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Remove task", role: .destructive) {
                Task {
                    await model.removeTask(id: planItemID)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your service history for this task is kept. Only the schedule is removed.")
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func scheduleSection(item: MaintenancePlanItem, evaluation: ScheduleEvaluation) -> some View {
        Section {
            if let rule = item.effectiveRule {
                VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                    Text(rule.summary)
                        .font(.body)
                    if let caveat = rule.caveat {
                        Text(caveat)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ProvenanceLabel(provenance: item.effectiveProvenance)
                }
                .padding(.vertical, 2)
            } else {
                VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                    Text("No schedule yet")
                        .font(.body.weight(.medium))
                    Text("Odomind does not publish an interval for this task, because the right one depends on your specific vehicle. Enter the interval from your owner's manual and Odomind will track it from there.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 2)
            }

            Button(item.effectiveRule == nil ? "Set the interval" : "Change the schedule") {
                showingScheduleEditor = true
            }

            if item.isOwnerOverridden, let catalogRule = item.catalogRule {
                Button("Use the published schedule (\(catalogRule.summary))") {
                    model.clearOwnerRule(planItemID: planItemID)
                }
                .font(.callout)
            }
        } header: {
            Text("Schedule")
        }

        if let proposal = item.pendingProposal {
            Section {
                VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                    Text(proposal.summaryOfChange)
                        .font(.callout)
                    Text("Catalog \(proposal.catalogVersion), proposed \(Format.date(proposal.proposedOn)). Your current schedule is still in use.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Use the new schedule") { model.acceptProposal(planItemID: planItemID) }
                Button("Keep mine", role: .cancel) { model.dismissProposal(planItemID: planItemID) }
            } header: {
                Label("Schedule change available", systemImage: "bell.badge")
            }
        }
    }

    @ViewBuilder
    private func dueSection(evaluation: ScheduleEvaluation, vehicle: Vehicle) -> some View {
        if evaluation.nextDueOdometer != nil || evaluation.nextDueDate != nil || evaluation.estimatedDueDate != nil {
            Section("Next due") {
                if let odometer = evaluation.nextDueOdometer {
                    ValueRow(
                        label: "At odometer",
                        value: Format.distance(odometer.converted(to: vehicle.displayUnit)),
                        secondary: evaluation.distanceRemaining.map {
                            $0.amount > 0 ? "\(Format.distance($0)) to go" : "\(Format.distance($0.magnitude)) past"
                        },
                        symbolName: "gauge.with.dots.needle.33percent"
                    )
                }
                if let date = evaluation.nextDueDate {
                    ValueRow(
                        label: "By date",
                        value: Format.longDate(date),
                        secondary: evaluation.daysRemaining.map {
                            $0 >= 0 ? "\(Format.dayCount($0)) to go" : "\(Format.dayCount($0)) past"
                        },
                        symbolName: "calendar"
                    )
                }
                if let estimated = evaluation.estimatedDueDate {
                    VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                        ValueRow(
                            label: "Estimated",
                            value: Format.longDate(estimated),
                            secondary: evaluation.estimateConfidence.map { "\($0.displayName) estimate" },
                            symbolName: "chart.line.uptrend.xyaxis"
                        )
                        Text("A projection from how far you usually drive, not a confirmed date. Update your mileage to replace it with a real one.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func historySection(item: MaintenancePlanItem, vehicle: Vehicle) -> some View {
        let records = model.serviceRecords(for: vehicle.id)
            .filter { $0.includes(definitionID: item.definitionID) }

        Section {
            if records.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                    Text(baselineDescription(item))
                        .font(.callout)
                    if !item.baseline.isAnswered || !item.baseline.isKnown {
                        Button("Start tracking from today") {
                            model.startTrackingFromToday(planItemID: planItemID)
                        }
                        .font(.callout)
                        Text("Odomind records this as a starting point, not as work that was done.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if case .notProvided = item.baseline {
                        Button("I don't know when this was last done") {
                            model.setBaseline(.unknownToOwner, planItemID: planItemID)
                        }
                        .font(.callout)
                    }
                }
                .padding(.vertical, 2)
            } else {
                ForEach(records.prefix(5)) { record in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(Format.date(record.performedOn))
                            Spacer()
                            if let odometer = record.odometer {
                                Text(Format.distance(odometer))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(record.performer.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        } header: {
            Text("Service history")
        } footer: {
            if records.count > 5 {
                Text("Showing the 5 most recent of \(records.count). The full list is in History.")
            }
        }
    }

    @ViewBuilder
    private func specificationsSection(item: MaintenancePlanItem, vehicle: Vehicle) -> some View {
        if !item.relatedSpecifications.isEmpty {
            let resolved = model.resolvedSpecifications(for: vehicle)
            let relevant = item.relatedSpecifications
            Section {
                ForEach(relevant, id: \.self) { kind in
                    if let match = resolved.first(where: { $0.kind == kind }) {
                        VStack(alignment: .leading, spacing: 2) {
                            ValueRow(label: kind.displayName, value: match.active.value.displayString)
                            ProvenanceLabel(provenance: match.active.provenance, sourceName: match.sourceName)
                        }
                        .padding(.vertical, 2)
                    } else {
                        UnavailableValueRow(label: kind.displayName)
                    }
                }
            } header: {
                Text("Specifications")
            } footer: {
                Text("Odomind shows a value only when it has one it can stand behind. Anything you add here is stored against this vehicle and used everywhere.")
            }
        }
    }

    @ViewBuilder
    private func actionsSection(item: MaintenancePlanItem, evaluation: ScheduleEvaluation, vehicle: Vehicle) -> some View {
        Section {
            Button {
                showingServiceLog = true
            } label: {
                Label("Log this service", systemImage: "checkmark.seal")
            }

            Button {
                showingSnoozeOptions = true
            } label: {
                Label(item.snoozedUntil == nil ? "Snooze reminders" : "Change snooze", systemImage: "bell.slash")
            }

            if evaluation.nextDueDate != nil || evaluation.estimatedDueDate != nil {
                Button {
                    if model.calendarExportState(planItemID: planItemID).hasEvent {
                        showingDuplicateCalendarWarning = true
                    } else {
                        presentCalendarEditor(evaluation: evaluation, vehicle: vehicle, item: item)
                    }
                } label: {
                    Label("Add to Calendar", systemImage: "calendar.badge.plus")
                }
            }
        } footer: {
            calendarFooter(item: item)
        }
    }

    @ViewBuilder
    private func calendarFooter(item: MaintenancePlanItem) -> some View {
        switch model.calendarExportState(planItemID: planItemID) {
        case .notExported:
            Text("Adding to Calendar creates a one-off event you confirm yourself. Odomind does not read your calendar, and it cannot change or remove the event later.")
        case .exported(let on):
            Text("You added this to your calendar on \(Format.date(on)). Odomind cannot update or remove that event.")
        case .exportedButStale(let on, let eventDate):
            Text("You added this to your calendar on \(Format.date(on)) with a date of \(Format.date(eventDate)). The schedule has changed since, and Odomind cannot update that event — edit or delete it in Calendar.")
        }
    }

    @ViewBuilder
    private func reminderSection(item: MaintenancePlanItem) -> some View {
        Section {
            Toggle(
                "Remind me",
                isOn: Binding(
                    get: { item.reminder.isEnabled },
                    set: { newValue in
                        var preference = item.reminder
                        preference.isEnabled = newValue
                        model.setReminder(preference, planItemID: planItemID)
                        if newValue, !model.snapshot.settings.reminders.remindersEnabled {
                            Task { _ = await model.enableReminders() }
                        }
                    }
                )
            )
            if item.reminder.isEnabled {
                Stepper(
                    "Lead time: \(Format.dayCount(item.reminder.leadDays)) before",
                    value: Binding(
                        get: { item.reminder.leadDays },
                        set: { newValue in
                            var preference = item.reminder
                            preference = ReminderPreference(
                                isEnabled: preference.isEnabled,
                                leadDays: newValue,
                                hour: preference.hour,
                                minute: preference.minute
                            )
                            model.setReminder(preference, planItemID: planItemID)
                        }
                    ),
                    in: 0...60
                )
            }
        } header: {
            Text("Reminder")
        } footer: {
            if item.reminder.isEnabled, !model.snapshot.settings.reminders.remindersEnabled {
                Text("Reminders are turned off for Odomind, so nothing will be delivered. Turn them on in Garage → Settings → Reminders.")
            } else {
                Text("Reminders use dates Odomind is confident about. A reminder built from a mileage estimate says so.")
            }
        }
    }

    @ViewBuilder
    private func manageSection(item: MaintenancePlanItem) -> some View {
        Section {
            Toggle(
                "Track this task",
                isOn: Binding(
                    get: { item.isEnabled },
                    set: { model.setTaskEnabled($0, planItemID: planItemID) }
                )
            )
            Button("Remove from this vehicle", role: .destructive) {
                showingDeleteConfirmation = true
            }
        } footer: {
            Text("Turning tracking off hides this from Today without losing your history.")
        }
    }

    // MARK: - Helpers

    private func baselineDescription(_ item: MaintenancePlanItem) -> String {
        switch item.baseline {
        case .notProvided:
            return "No history recorded. Odomind will not assume this was just done."
        case .unknownToOwner:
            return "You told Odomind you do not know when this was last done."
        case .declared(let date, let odometer):
            var parts: [String] = []
            if let date { parts.append("from \(Format.date(date))") }
            if let odometer { parts.append("at \(Format.distance(odometer))") }
            return parts.isEmpty
                ? "Tracking from a starting point you set."
                : "Tracking \(parts.joined(separator: " ")) — a starting point you set, not a recorded service."
        }
    }

    private func noticeKind(for reason: EvaluationReason) -> InlineNotice.Kind {
        switch reason {
        case .overdueByDistance, .overdueByDays, .milestoneAlreadyPassed:
            return .caution
        default:
            return .information
        }
    }

    private func duplicateCalendarMessage(item: MaintenancePlanItem) -> String {
        switch model.calendarExportState(planItemID: planItemID) {
        case .exported(let on):
            return "You already added this to your calendar on \(Format.date(on)). Odomind cannot see or remove that event, so adding again creates a second one."
        case .exportedButStale(let on, let eventDate):
            return "You added this on \(Format.date(on)) with a date of \(Format.date(eventDate)), and the schedule has changed since. Odomind cannot update the old event, so adding now creates a second one."
        case .notExported:
            return ""
        }
    }

    private func presentCalendarEditor(evaluation: ScheduleEvaluation, vehicle: Vehicle, item: MaintenancePlanItem) {
        guard let due = evaluation.nextDueDate ?? evaluation.estimatedDueDate else { return }
        let service = CalendarService()
        guard let event = service.makeEvent(
            title: item.title,
            vehicleName: vehicle.displayName,
            dueDate: due,
            isEstimated: evaluation.nextDueDate == nil,
            scheduleSummary: item.effectiveRule?.summary,
            calendar: model.calendar
        ) else {
            return
        }
        calendarEvent = CalendarEventDraft(event: event)
    }
}

/// Wraps an `EKEvent` so it can drive a `sheet(item:)` without conforming a
/// framework class to `Identifiable`.
struct CalendarEventDraft: Identifiable {
    let id = UUID()
    let event: EKEvent
}
