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
enum CalendarService {

    /// Builds an all-day event for a maintenance deadline, together with the
    /// store it belongs to.
    ///
    /// EventKit objects must outlive their store, so the draft carries both and
    /// the view holds the draft for as long as the editor is on screen.
    static func makeEventDraft(
        title: String,
        vehicleName: String,
        dueDate: Date,
        isEstimated: Bool,
        scheduleSummary: String?,
        calendar: Calendar
    ) -> CalendarEventDraft {
        // Constructing a store does not request authorization and reads nothing.
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = "\(title) — \(vehicleName)"
        event.isAllDay = true

        // An all-day EKEvent ends on the last day it covers, not on the
        // morning after. Passing an exclusive end date here makes EventKit
        // stretch the entry to 23:59:59 of that following day, which puts a
        // two-day block on the owner's calendar for a one-day deadline.
        let day = calendar.startOfDay(for: dueDate)
        event.startDate = day
        event.endDate = day

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

        return CalendarEventDraft(store: store, event: event)
    }
}

/// An event waiting to be shown in the system editor, with the store that owns
/// it. Identifiable so it can drive `sheet(item:)` without conforming an
/// EventKit class to `Identifiable`.
struct CalendarEventDraft: Identifiable {
    let id = UUID()
    let store: EKEventStore
    let event: EKEvent
}
