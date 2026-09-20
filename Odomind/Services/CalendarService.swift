import EventKit
import Foundation
import OdomindCore

/// Adds a single maintenance deadline to the owner's calendar.
///
/// On iOS 17 and later `EKEventEditViewController` runs outside the app's
/// process and has its own access to the calendar, so Odomind presents the
/// system editor **without requesting calendar permission at all**. The owner
/// sees what will be saved, picks the calendar, and confirms. Odomind never
/// reads their calendar and never writes without them tapping Add.
///
/// What Odomind cannot do, and says so in the UI: keep that event in step.
/// A saved event is a snapshot of the due date at the moment it was created.
/// Updating or removing it later would need full calendar access and stored
/// event identifiers, which this version deliberately does not ask for.
@MainActor
final class CalendarService {
    /// A store is needed to construct the event object. No authorization is
    /// requested, and no calendar is read through it.
    private let store = EKEventStore()

    /// Builds an all-day event for a maintenance deadline.
    ///
    /// Returns `nil` only when the due date cannot be represented, which the
    /// caller reports rather than silently skipping.
    func makeEvent(
        title: String,
        vehicleName: String,
        dueDate: Date,
        isEstimated: Bool,
        scheduleSummary: String?,
        calendar: Calendar
    ) -> EKEvent? {
        let event = EKEvent(eventStore: store)
        event.title = "\(title) — \(vehicleName)"
        event.isAllDay = true

        let day = calendar.startOfDay(for: dueDate)
        guard let end = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
        event.startDate = day
        event.endDate = end

        var notes: [String] = []
        if let scheduleSummary {
            notes.append("Schedule: \(scheduleSummary)")
        }
        if isEstimated {
            notes.append(
                "This date is an estimate based on how far you usually drive, not a confirmed deadline."
            )
        }
        notes.append(
            "Added from Odomind. This event is a one-off snapshot: if the due date changes in Odomind, this event will not update."
        )
        event.notes = notes.joined(separator: "\n\n")

        return event
    }
}
