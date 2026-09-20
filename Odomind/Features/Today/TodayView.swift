import SwiftUI
import OdomindCore

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationRouter.self) private var router

    @State private var showingMileageEntry = false
    @State private var showingServiceLog = false
    @State private var expandedGroups: Set<DueState> = [.overdue, .dueSoon]

    var body: some View {
        NavigationStack {
            Group {
                if let vehicle = model.selectedVehicle {
                    content(for: vehicle)
                } else {
                    NoVehicleView()
                }
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    VehiclePickerBar()
                }
            }
            .sheet(isPresented: $showingMileageEntry) {
                if let vehicle = model.selectedVehicle {
                    MileageEntrySheet(vehicle: vehicle)
                }
            }
            .sheet(isPresented: $showingServiceLog) {
                if let vehicle = model.selectedVehicle {
                    LogServiceView(vehicle: vehicle)
                }
            }
            .onChange(of: router.presentMileageEntry) { _, newValue in
                if newValue {
                    showingMileageEntry = true
                    router.presentMileageEntry = false
                }
            }
            .onChange(of: router.presentServiceLog) { _, newValue in
                if newValue {
                    showingServiceLog = true
                    router.presentServiceLog = false
                }
            }
        }
    }

    @ViewBuilder
    private func content(for vehicle: Vehicle) -> some View {
        List {
            Section {
                MileageSummaryRow(vehicle: vehicle) {
                    showingMileageEntry = true
                }
            }

            Section {
                HStack(spacing: Theme.Spacing.medium) {
                    PrimaryActionButton(title: "Update mileage", symbolName: "gauge.with.dots.needle.33percent") {
                        showingMileageEntry = true
                    }
                    .accessibilityIdentifier("today.updateMileage")
                    PrimaryActionButton(title: "Log service", symbolName: "checkmark.seal") {
                        showingServiceLog = true
                    }
                    .accessibilityIdentifier("today.logService")
                }
                .listRowInsets(EdgeInsets(top: Theme.Spacing.small, leading: 0, bottom: Theme.Spacing.small, trailing: 0))
                .listRowBackground(Color.clear)
            }

            if vehicle.isDemo, let disclaimer = model.demoDisclaimer {
                Section {
                    InlineNotice(kind: .caution, message: disclaimer)
                }
            }

            if model.openProposalCount > 0 {
                Section {
                    Button {
                        router.selectedTab = .maintenance
                        router.maintenancePath = [.proposals]
                    } label: {
                        Label(
                            "\(model.openProposalCount) schedule change\(model.openProposalCount == 1 ? "" : "s") to review",
                            systemImage: "bell.badge"
                        )
                    }
                }
            }

            let groups = model.grouped(for: vehicle.id)
            if groups.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No tasks yet", systemImage: "wrench.and.screwdriver")
                    } description: {
                        Text("Add the maintenance you want Odomind to track.")
                    } actions: {
                        Button("Add tasks") {
                            router.selectedTab = .maintenance
                            router.maintenancePath = [.addTask]
                        }
                    }
                }
            } else if !groups.contains(where: { $0.state == .overdue || $0.state == .dueSoon }) {
                Section {
                    // Deliberately about the records, not the vehicle. Odomind
                    // has no idea whether the car is mechanically healthy.
                    Label {
                        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                            Text("Nothing currently due based on your records")
                                .font(.body.weight(.medium))
                            Text("Odomind can only go on what you have told it. Keep your mileage up to date for this to stay accurate.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(.green)
                    }
                }
            }

            ForEach(groups) { group in
                Section {
                    ForEach(group.items) { evaluation in
                        NavigationLink(value: evaluation.planItemID) {
                            TaskSummaryRow(evaluation: evaluation, vehicle: vehicle)
                        }
                    }
                } header: {
                    HStack(spacing: Theme.Spacing.small) {
                        Image(systemName: group.state.symbolName)
                            .foregroundStyle(group.state.tint)
                        Text(group.state.displayName)
                        Spacer()
                        Text("\(group.items.count)")
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text(group.state.groupExplanation)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationDestination(for: UUID.self) { planItemID in
            TaskDetailView(planItemID: planItemID)
        }
        .refreshable {
            model.refresh()
            await model.syncReminders()
        }
    }
}

/// The mileage header: what Odomind knows, when it learned it, and how stale
/// that is.
struct MileageSummaryRow: View {
    @Environment(AppModel.self) private var model
    let vehicle: Vehicle
    let update: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            HStack(alignment: .firstTextBaseline) {
                Text(vehicle.displayName)
                    .font(.headline)
                Spacer()
                if vehicle.isDemo {
                    Text("SAMPLE")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: Theme.Radius.badge))
                        .foregroundStyle(.orange)
                }
            }

            if let reading = model.latestReading(for: vehicle.id) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.small) {
                    Text(Format.distanceNumber(reading.value))
                        .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                    Text(reading.value.unit.abbreviation)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("Recorded odometer \(Format.distance(reading.value))"))

                Text(stalenessText(for: reading))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No odometer reading yet")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Button("Add your current mileage", action: update)
                    .font(.callout.weight(.medium))
                    .buttonStyle(.borderless)
            }

            if let estimate = model.estimate(for: vehicle.id) {
                switch estimate {
                case .available(let value):
                    Label(value.explanation, systemImage: "chart.line.uptrend.xyaxis")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .unavailable(let reason):
                    Label(reason.message, systemImage: "chart.line.flattrend.xyaxis")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, Theme.Spacing.tight)
    }

    private func stalenessText(for reading: OdometerReading) -> String {
        let days = DateSupport.dayCount(from: reading.recordedOn, to: model.clock.now, in: model.calendar)
        let dateText = Format.date(reading.recordedOn)
        switch days {
        case ..<0: return "Recorded \(dateText)"
        case 0: return "Recorded today"
        case 1: return "Recorded yesterday"
        case 2...45: return "Recorded \(dateText) · \(days) days ago"
        default: return "Recorded \(dateText) · \(days) days ago, so next-due information may be out of date"
        }
    }
}

/// One task in the Today list.
struct TaskSummaryRow: View {
    @Environment(AppModel.self) private var model
    let evaluation: ScheduleEvaluation
    let vehicle: Vehicle

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.small) {
                Text(evaluation.title)
                    .font(.body)
                if evaluation.isSnoozed {
                    Image(systemName: "bell.slash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(Text("Reminders snoozed"))
                }
            }

            Text(DueSummary.text(for: evaluation, calendar: model.calendar, now: model.clock.now))
                .font(.caption)
                .foregroundStyle(evaluation.state == .overdue ? Color.red : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// Turns an evaluation into the one line that explains it.
///
/// Every screen uses this, so the wording an owner sees in a list, on a detail
/// screen and in a notification is the same wording.
enum DueSummary {
    static func text(for evaluation: ScheduleEvaluation, calendar: Calendar, now: Date) -> String {
        switch evaluation.state {
        case .overdue:
            return overdueText(evaluation)
        case .dueSoon, .upcoming:
            return upcomingText(evaluation, calendar: calendar, now: now)
        case .historyUnknown:
            return "History unknown — set a starting point to schedule this."
        case .needsSetup:
            return evaluation.reasons.first?.message ?? "Needs setup."
        case .completed:
            return evaluation.reasons.first?.message ?? "Completed."
        case .notApplicable:
            return evaluation.reasons.first?.message ?? "Does not apply to this vehicle."
        }
    }

    private static func overdueText(_ evaluation: ScheduleEvaluation) -> String {
        var parts: [String] = []
        if let distance = evaluation.distanceRemaining, distance.amount <= 0 {
            parts.append("\(Format.distance(distance.magnitude)) past due")
        }
        if let days = evaluation.daysRemaining, days < 0 {
            parts.append("\(Format.dayCount(days)) past due")
        }
        if parts.isEmpty { return "Overdue based on your records." }
        return parts.joined(separator: " · ")
    }

    private static func upcomingText(_ evaluation: ScheduleEvaluation, calendar: Calendar, now: Date) -> String {
        var parts: [String] = []
        if let distance = evaluation.distanceRemaining, distance.amount > 0 {
            parts.append("in \(Format.distance(distance))")
        }
        if let dueDate = evaluation.nextDueDate {
            parts.append("by \(Format.relativeDay(dueDate, from: now, calendar: calendar))")
        } else if let estimated = evaluation.estimatedDueDate {
            let confidence = evaluation.estimateConfidence?.displayName.lowercased() ?? "rough"
            parts.append("around \(Format.relativeDay(estimated, from: now, calendar: calendar)) (\(confidence) estimate)")
        }
        if parts.isEmpty {
            return evaluation.reasons.first?.message ?? "Scheduled."
        }
        return "Due " + parts.joined(separator: ", ")
    }

    /// The "due by distance, by date, or both" line shown on a task's detail.
    static func basisText(for evaluation: ScheduleEvaluation) -> String {
        switch evaluation.basis {
        case .distance: return "Due by distance"
        case .date: return "Due by date"
        case .both: return "Due by distance and date, whichever comes first"
        case .indicator: return "Driven by a message on your dashboard"
        case .none: return "Not currently scheduled"
        }
    }
}
