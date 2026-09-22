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
    @State private var showsSchedule = false
    @State private var showsHistory = false

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
            // Status and the action that resolves it, together, above the
            // fold. Build 1 put three explanatory cards between the two, which
            // is how "Log this service" ended up below the bottom of the
            // screen on the job most likely to need it.
            Section {
                VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                    DueBadge(state: evaluation.state)
                    Text(DueSummary.text(for: evaluation, calendar: model.calendar, now: model.clock.now))
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    if let last = lastCompletionText(item: item, evaluation: evaluation) {
                        Text(last)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, Theme.Spacing.tight)

                Button {
                    showingServiceLog = true
                } label: {
                    Label("Mark as done", systemImage: "checkmark.seal")
                        .font(.body.weight(.medium))
                }
                .accessibilityIdentifier("task.markDone")

                if Self.canStartTrackingFromToday(item: item, evaluation: evaluation) {
                    Button {
                        model.startTrackingFromToday(planItemID: planItemID)
                    } label: {
                        Label("Start tracking from today", systemImage: "flag")
                    }
                    .accessibilityIdentifier("task.startTracking")
                }
            } header: {
                Text("Status")
            } footer: {
                if Self.canStartTrackingFromToday(item: item, evaluation: evaluation) {
                    Text("A starting point, not work done.")
                }
            }

            if !item.purpose.isEmpty {
                Section("What this is for") {
                    Text(item.purpose)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(difficultyNote(item: item))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let safetyNote = item.safetyNote {
                Section {
                    InlineNotice(kind: .safety, message: safetyNote)
                }
            }

            specificationsSection(item: item, vehicle: vehicle)
            costSection(item: item, vehicle: vehicle)

            // Everything below here is reference rather than action, so it is
            // collapsed by default. One tap reveals the lot; nobody has to
            // scroll past it to reach the thing they came for.
            // Reference rather than action, so each one collapses. Nobody
            // has to scroll past a schedule provenance line to reach the
            // button that records the work.
            scheduleDetail(item: item, evaluation: evaluation)
            dueDetail(evaluation: evaluation, vehicle: vehicle)
            historyDetail(item: item, vehicle: vehicle)

            calendarAndSnoozeSection(item: item, evaluation: evaluation, vehicle: vehicle)
            reminderSection(item: item)
            manageSection(item: item)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(LuminousField(strength: 0.5))
        .sheet(isPresented: $showingScheduleEditor) {
            ScheduleEditor(planItemID: planItemID)
        }
        .sheet(isPresented: $showingServiceLog) {
            LogServiceView(vehicle: vehicle, preselectedPlanItemID: planItemID)
        }
        .sheet(item: $calendarEvent) { draft in
            EventEditView(event: draft.event, eventStore: draft.store) { action in
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
            Text("Pauses reminders. The due date does not change.")
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
            Text("Your history is kept. Only the schedule goes.")
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func scheduleDetail(item: MaintenancePlanItem, evaluation: ScheduleEvaluation) -> some View {
        Section {
            DisclosureGroup("Schedule and source", isExpanded: $showsSchedule) {
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
                    Text("The right interval depends on your car. Enter it from the owner's manual and Odomind tracks it.")
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
            }
            .accessibilityIdentifier("task.scheduleDisclosure")
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
    private func dueDetail(evaluation: ScheduleEvaluation, vehicle: Vehicle) -> some View {
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
                        Text("Projected from how far you drive. Update your mileage for a real date.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func historyDetail(item: MaintenancePlanItem, vehicle: Vehicle) -> some View {
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
                        Text("Recorded as a starting point, not as work done.")
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
                Text("5 of \(records.count). The rest is in History.")
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
                        UnavailableValueRow(
                            label: kind.displayName,
                            explanation: kind.sourceHint
                        )
                    }
                }
            } header: {
                Text("Specifications")
            } footer: {
                Text("Shown only when Odomind has a value it can stand behind. Anything you add is used everywhere.")
            }
        }
    }

    @ViewBuilder
    private func calendarAndSnoozeSection(item: MaintenancePlanItem, evaluation: ScheduleEvaluation, vehicle: Vehicle) -> some View {
        Section {
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
            Text("Creates a one-off event you confirm. Odomind cannot change or remove it later.")
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
                Text("Reminders are off for Odomind. Turn them on in Settings → Reminders.")
            } else {
                Text("A reminder built from an estimate says so.")
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
            Text("Hides this without losing your history.")
        }
    }

    /// Parts and money.
    ///
    /// Four different things live here and are never blurred together: what
    /// this owner has actually paid, a budget they set themselves, a regional
    /// estimate (which Odomind does not have a source for and therefore does
    /// not show), and a live offer (which needs a provider Odomind does not
    /// have). Only the first two are real, so only the first two appear.
    @ViewBuilder
    private func costSection(item: MaintenancePlanItem, vehicle: Vehicle) -> some View {
        let past = pastCosts(item: item, vehicle: vehicle)
        Section {
            if let total = past.total, past.count > 0 {
                ValueRow(
                    label: "You have paid",
                    value: Format.moneyTotal(total),
                    secondary: "across \(past.count) recorded visit\(past.count == 1 ? "" : "s")"
                )
            } else {
                QuietNote(
                    text: "No cost recorded for this job yet. Add one when you log the work and Odomind will keep a running total.",
                    symbolName: "dollarsign.circle"
                )
            }

            // Carries the job, what it is called, and the category it sits
            // in — so an oil change opens looking for an oil filter rather
            // than at a blank field. The job's own name is the better query:
            // "Engine oil and filter" finds a filter, "Engine" does not.
            NavigationLink(value: JobRoute.parts(PartsDestination(
                planItemID: planItemID,
                query: item.title,
                category: item.category.displayName
            ))) {
                Label("Find parts", systemImage: "bag")
            }
            .accessibilityIdentifier("task.findParts")
        } header: {
            Text("Parts and cost")
        } footer: {
            // No invented "typical cost in your area". Odomind has no source
            // for one, and a made-up number beside a real one is worse than
            // no number at all.
            Text("No price estimates — only what you have actually spent.")
        }
    }

    private func pastCosts(item: MaintenancePlanItem, vehicle: Vehicle) -> (total: MoneyTotal?, count: Int) {
        let records = model.serviceRecords(for: vehicle.id)
            .filter { $0.includes(definitionID: item.definitionID) }
        let amounts = records.compactMap { record -> Money? in
            if let line = record.items.first(where: { $0.definitionID == item.definitionID }),
               let cost = line.itemCost {
                return cost
            }
            // A single-job visit's total is that job's cost. A visit covering
            // several jobs is not divided up, because Odomind has no basis to
            // split it and a guessed split would be a fabricated number.
            return record.items.count == 1 ? record.totalCost : nil
        }
        guard !amounts.isEmpty else { return (nil, 0) }
        return (MoneyTotal.total(of: amounts), amounts.count)
    }

    /// The last recorded completion, on the status block.
    /// Whether to offer "Start tracking from today".
    ///
    /// Only where the baseline is genuinely unknown. Build 2 asked whether the
    /// *baseline field* was set, which is not the same question: a job with a
    /// real recorded service — "Last done Mar 5, 2026 at 123,800 mi" — could
    /// still have an empty baseline, so the screen showed a completion and an
    /// offer to invent one directly beneath it. Taking that offer would have
    /// written today over history the owner had already entered.
    static func canStartTrackingFromToday(item: MaintenancePlanItem, evaluation: ScheduleEvaluation) -> Bool {
        // A recorded service *is* the baseline.
        guard evaluation.lastCompletedOn == nil, evaluation.lastCompletedOdometer == nil else { return false }
        return item.baseline == .notProvided || evaluation.state == .historyUnknown
    }

    private func lastCompletionText(item: MaintenancePlanItem, evaluation: ScheduleEvaluation) -> String? {
        if let date = evaluation.lastCompletedOn {
            var text = "Last done \(Format.date(date))"
            if let odometer = evaluation.lastCompletedOdometer {
                text += " at \(Format.distance(odometer))"
            }
            return text
        }
        switch item.baseline {
        case .unknownToOwner:
            return "You told Odomind you do not know when this was last done."
        case .notProvided:
            return "No completion recorded yet."
        default:
            return nil
        }
    }

    /// Whether this is a driveway job or a shop job.
    ///
    /// Derived from the kind of work rather than invented per vehicle, and
    /// worded as a general statement, because Odomind has no idea what tools
    /// this particular owner has.
    private func difficultyNote(item: MaintenancePlanItem) -> String {
        switch item.action {
        case .inspect, .clean, .recordIndicator:
            return "Usually a look rather than a job — most people can do this themselves in a few minutes."
        case .test, .serviceOrFlush, .adjust:
            return "Usually a shop job: this needs equipment most people do not have at home."
        case .replace, .rotate, .topOff:
            switch item.category {
            case .tiresAndWheels, .brakes, .drivetrain, .suspensionAndSteering:
                return "Commonly done by a shop — this usually wants a lift and a torque wrench."
            default:
                return "Often a do-it-yourself job with basic tools, and every shop does it too."
            }
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
        calendarEvent = CalendarService.makeEventDraft(
            title: item.title,
            vehicleName: vehicle.displayName,
            dueDate: due,
            isEstimated: evaluation.nextDueDate == nil,
            scheduleSummary: item.effectiveRule?.summary,
            calendar: model.calendar
        )
    }
}
