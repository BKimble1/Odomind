import SwiftUI
import UIKit
import EventKit
import OdomindCore

/// The review step before Odomind writes anything into the owner's calendar.
///
/// Nothing is written without this screen: what will be created, for which
/// vehicle, on which dates, with a warning on anything already exported so a
/// second tap does not silently produce a duplicate. The wording says "copy"
/// rather than "sync", because a copy is what a write-only export can be.
struct CalendarExportReview: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var selected: Set<UUID> = []
    @State private var isWorking = false
    @State private var outcome: CalendarExportOutcome?
    @State private var didPrepare = false

    var body: some View {
        NavigationStack {
            Group {
                if candidates.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing to add", systemImage: "calendar.badge.exclamationmark")
                    } description: {
                        if model.selectedVehicle?.isDemo == true {
                            Text("This is the sample vehicle. Odomind does not put fictional dates in your calendar.")
                        } else {
                            Text("Odomind only exports deadlines it has a date for. Jobs that are due at a mileage have no date until it knows how far you drive.")
                        }
                    }
                } else {
                    list
                }
            }
            .navigationTitle("Add to calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(selected.count)") { Task { await export() } }
                        .disabled(selected.isEmpty || isWorking)
                        .accessibilityIdentifier("calendarExport.confirm")
                }
            }
            .onAppear(perform: prepare)
        }
    }

    private var list: some View {
        Form {
            Section {
                ForEach(candidates) { candidate in
                    Button {
                        toggle(candidate.planItemID)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.medium) {
                            Image(systemName: selected.contains(candidate.planItemID) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(
                                    selected.contains(candidate.planItemID)
                                        ? Theme.Palette.accent : Theme.Palette.secondaryText
                                )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(candidate.title)
                                    .foregroundStyle(Theme.Palette.primaryText)
                                Text(detail(for: candidate))
                                    .font(.caption)
                                    .foregroundStyle(Theme.Palette.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("calendarExport.item")
                }
            } header: {
                Text("Next \(model.calendarProjectionMonths) months")
            } footer: {
                Text("Odomind adds these as one-off events in your default calendar. It cannot read your calendar, so it cannot tell you what is already there, and it will not update or remove these later.")
            }

            if let outcome {
                Section {
                    switch outcome {
                    case .written(let count):
                        Label("Added \(count) event\(count == 1 ? "" : "s").", systemImage: "checkmark.circle")
                            .foregroundStyle(Theme.Colors.done)
                    case .accessDenied:
                        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                            Label("Calendar access is off", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(Theme.Colors.caution)
                            Text("Odomind cannot add events without permission. Everything else in the app keeps working, and you can still add a single event from a job screen.")
                                .font(.footnote)
                                .foregroundStyle(Theme.Palette.secondaryText)
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                Link("Open Odomind's settings", destination: url)
                            }
                        }
                    case .failed(let message):
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.Colors.overdue)
                    }
                }
            }
        }
    }

    private var candidates: [CalendarExportCandidate] {
        // The sample vehicle never reaches the owner's real calendar. It is
        // fictional, it is already excluded from reminders and reports, and a
        // made-up deadline sitting in somebody's calendar next to real ones is
        // exactly the kind of thing nobody would notice until it mattered.
        guard let vehicle = model.selectedVehicle, !vehicle.isDemo else { return [] }
        let now = model.clock.now
        let horizon = model.calendar.date(
            byAdding: .month, value: model.calendarProjectionMonths, to: now
        ) ?? now

        return model.evaluations(for: vehicle.id).compactMap { evaluation -> CalendarExportCandidate? in
            guard evaluation.state.isScheduled else { return nil }
            let isEstimated = evaluation.nextDueDate == nil
            guard let date = evaluation.nextDueDate ?? evaluation.estimatedDueDate, date <= horizon else {
                return nil
            }
            let item = model.planItem(id: evaluation.planItemID)
            return CalendarExportCandidate(
                planItemID: evaluation.planItemID,
                title: evaluation.title,
                vehicleName: vehicle.displayName,
                dueDate: date,
                isEstimated: isEstimated,
                scheduleSummary: item?.effectiveRule?.summary,
                lastExportedOn: item?.lastCalendarExportOn,
                lastExportedDueDate: item?.lastCalendarExportDueDate
            )
        }
        .sorted { $0.dueDate < $1.dueDate }
    }

    private func detail(for candidate: CalendarExportCandidate) -> String {
        var parts = [Format.longDate(candidate.dueDate)]
        if candidate.isEstimated { parts.append("estimated") }
        if candidate.hasMovedSinceExport {
            parts.append("already added, but the date has moved since")
        } else if candidate.wasExportedBefore {
            parts.append("already added — adding again makes a second event")
        }
        return parts.joined(separator: " · ")
    }

    /// Pre-ticks what is genuinely worth adding: things never exported, and
    /// things whose date has moved. Never something already in the calendar at
    /// the same date.
    private func prepare() {
        guard !didPrepare else { return }
        didPrepare = true
        selected = Set(
            candidates
                .filter { !$0.wasExportedBefore || $0.hasMovedSinceExport }
                .map(\.planItemID)
        )
    }

    private func toggle(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func export() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        let chosen = candidates.filter { selected.contains($0.planItemID) }
        let result = await CalendarService.export(
            chosen,
            addAlarm: model.preferences.calendar.addAlarmsToExportedEvents,
            calendar: model.calendar
        )
        outcome = result

        if case .written = result {
            for candidate in chosen {
                model.markCalendarExported(planItemID: candidate.planItemID, dueDate: candidate.dueDate)
            }
        }
    }
}
