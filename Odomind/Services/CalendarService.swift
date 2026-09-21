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

// MARK: - Batch export

/// One candidate event in a batch export.
struct CalendarExportCandidate: Identifiable, Hashable {
    var id: UUID { planItemID }
    var planItemID: UUID
    var title: String
    var vehicleName: String
    var dueDate: Date
    var isEstimated: Bool
    var scheduleSummary: String?
    /// When Odomind last wrote this one out, so the review can warn rather
    /// than quietly creating a second copy.
    var lastExportedOn: Date?
    var lastExportedDueDate: Date?

    var wasExportedBefore: Bool { lastExportedOn != nil }

    /// True when a previous export is now out of date, which is the one case
    /// where exporting again is clearly worth doing.
    var hasMovedSinceExport: Bool {
        guard let previous = lastExportedDueDate else { return false }
        return previous != dueDate
    }
}

enum CalendarExportOutcome: Equatable {
    case written(count: Int)
    case accessDenied
    case failed(String)
}

extension CalendarService {
    /// Asks for the least access that can actually do this.
    ///
    /// Writing a batch of events needs write-only access, and nothing more.
    /// Odomind does not read the owner's calendar here, cannot tell them what
    /// else is on it, and does not pretend otherwise.
    static func requestWriteAccess(store: EKEventStore) async -> Bool {
        do {
            return try await store.requestWriteOnlyAccessToEvents()
        } catch {
            return false
        }
    }

    static func writeAccessStatus() -> EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    /// Writes the chosen deadlines into the owner's default calendar.
    ///
    /// Each event is a snapshot with the same wording as a single export, so
    /// nobody ends up with two different explanations of the same date. The
    /// caller records what was written; this function does not, because it has
    /// no business touching the store.
    static func export(
        _ candidates: [CalendarExportCandidate],
        addAlarm: Bool,
        calendar: Calendar
    ) async -> CalendarExportOutcome {
        let store = EKEventStore()
        let status = writeAccessStatus()
        if status != .fullAccess && status != .writeOnly {
            guard await requestWriteAccess(store: store) else { return .accessDenied }
        }

        guard let destination = store.defaultCalendarForNewEvents else {
            return .failed("There is no calendar available to write to.")
        }

        var written = 0
        for candidate in candidates {
            let event = EKEvent(eventStore: store)
            event.calendar = destination
            event.title = "\(candidate.title) — \(candidate.vehicleName)"
            event.isAllDay = true

            // An all-day EKEvent ends on the last day it covers, not on the
            // morning after. An exclusive end date stretches a one-day
            // deadline into a two-day block.
            let day = calendar.startOfDay(for: candidate.dueDate)
            event.startDate = day
            event.endDate = day

            var notes: [String] = []
            if let summary = candidate.scheduleSummary { notes.append("Schedule: \(summary)") }
            if candidate.isEstimated {
                notes.append(
                    "This date is an estimate based on how far you usually drive, not a confirmed deadline."
                )
            }
            notes.append(
                "Added from Odomind. This event is a one-off copy: if the due date changes in Odomind, this event will not update."
            )
            event.notes = notes.joined(separator: "\n\n")

            if addAlarm {
                event.addAlarm(EKAlarm(relativeOffset: -60 * 60 * 9))
            }

            do {
                try store.save(event, span: .thisEvent, commit: false)
                written += 1
            } catch {
                return .failed((error as NSError).localizedDescription)
            }
        }

        do {
            try store.commit()
        } catch {
            return .failed((error as NSError).localizedDescription)
        }
        return .written(count: written)
    }
}
