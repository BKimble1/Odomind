import Foundation
import OdomindCore

/// Turns an evaluation into the one line that explains it.
///
/// Every screen uses this, so the wording an owner sees in a list, on a job
/// screen, in the calendar and in a notification is the same wording.
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

    /// The short form for a card or an agenda row, where the full sentence is
    /// more than the space deserves. "Due at 214,000 mi", "Estimated in
    /// November" — and nothing at all when neither is supported.
    static func compactText(
        for evaluation: ScheduleEvaluation,
        calendar: Calendar,
        now: Date
    ) -> String? {
        switch evaluation.state {
        case .overdue:
            return overdueText(evaluation)
        case .dueSoon, .upcoming:
            if let odometer = evaluation.nextDueOdometer {
                return "due at \(Format.distance(odometer))"
            }
            if let date = evaluation.nextDueDate {
                return "due \(Format.relativeDay(date, from: now, calendar: calendar))"
            }
            if let estimated = evaluation.estimatedDueDate {
                return "estimated \(Format.monthName(estimated, calendar: calendar))"
            }
            return nil
        case .historyUnknown:
            return "history unknown"
        case .needsSetup, .completed, .notApplicable:
            return nil
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

    /// The "due by distance, by date, or both" line shown on a job screen.
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
