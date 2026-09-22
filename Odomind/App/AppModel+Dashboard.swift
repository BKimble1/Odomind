import Foundation
import OdomindCore

/// What the dashboard needs, worked out once.
///
/// The board asks four questions — how is the car, what is next, how far this
/// month, how much of the plan is actually running — and every one of them is
/// derived from the same evaluations. Doing that in the view means four passes
/// and four chances to disagree with each other.
struct DashboardSummary: Hashable, Sendable {
    /// The worst state anything on the plan is in, which is the car's verdict.
    var worstState: DueState?
    /// The job that verdict came from.
    var headline: ScheduleEvaluation?
    /// Distance covered since the first reading of this calendar month.
    /// Absent when there is only one reading — one point is not a distance.
    var distanceThisMonth: Distance?
    /// Jobs with a schedule Odomind can actually run, over jobs tracked.
    var onTrack: Int
    var tracked: Int

    /// The one-word verdict. Deliberately short: a pill is not a sentence.
    var verdict: String {
        switch worstState {
        case .overdue: return "Needs attention"
        case .dueSoon: return "Due soon"
        case .needsSetup, .historyUnknown: return "Needs setup"
        case .none: return "Nothing tracked"
        default: return "Good"
        }
    }

    var verdictSymbol: String {
        switch worstState {
        case .overdue: return "exclamationmark.triangle.fill"
        case .dueSoon: return "clock.fill"
        case .needsSetup, .historyUnknown: return "slider.horizontal.3"
        case .none: return "questionmark.circle.fill"
        default: return "checkmark.circle.fill"
        }
    }
}

/// A job that comes due on a date rather than at a distance.
struct DateBasedItem: Hashable, Sendable {
    var planItemID: UUID
    var title: String
    var detail: String
}

extension AppModel {
    func dashboardSummary(for vehicleID: UUID) -> DashboardSummary {
        let evaluations = evaluations(for: vehicleID)
        let ranked = evaluations
            .filter { $0.state != .notApplicable && $0.state != .completed }
            .sorted { $0.state.sortRank < $1.state.sortRank }

        let headline = ranked.first
        let running = evaluations.filter {
            $0.state == .overdue || $0.state == .dueSoon || $0.state == .upcoming
        }
        let tracked = evaluations.filter { $0.state != .notApplicable }

        return DashboardSummary(
            worstState: headline?.state,
            headline: headline,
            distanceThisMonth: distanceThisMonth(for: vehicleID),
            onTrack: running.count,
            tracked: tracked.count
        )
    }

    /// How far the car has gone since the first reading recorded this month.
    ///
    /// Measured, never estimated. Two readings in the month are the minimum;
    /// with one, Odomind has a position and not a distance, and says nothing
    /// rather than implying zero.
    func distanceThisMonth(for vehicleID: UUID) -> Distance? {
        let now = clock.now
        guard let start = calendar.dateInterval(of: .month, for: now)?.start else { return nil }
        let readings = snapshot.readings(for: vehicleID)
            .filter { $0.recordedOn >= start && $0.recordedOn <= now }
            .sorted { $0.recordedOn < $1.recordedOn }
        guard let first = readings.first, let last = readings.last, readings.count > 1 else { return nil }
        // Converted before subtracting, because the two readings may have
        // been taken in different units — an owner who switched to kilometres
        // mid-month would otherwise get the difference of two unrelated
        // numbers.
        let unit = last.value.unit
        let delta = last.value.amount - first.value.converted(to: unit).amount
        guard delta > 0 else { return nil }
        return Distance(delta, unit)
    }

    /// The nearest job whose deadline is a date Odomind is confident about —
    /// an inspection, a renewal — rather than a projection from mileage.
    func nextDateBasedItem(for vehicleID: UUID) -> DateBasedItem? {
        let now = clock.now
        let candidate = evaluations(for: vehicleID)
            .filter { $0.state == .overdue || $0.state == .dueSoon || $0.state == .upcoming }
            .compactMap { evaluation -> (ScheduleEvaluation, Int)? in
                guard let due = evaluation.nextDueDate else { return nil }
                let days = DateSupport.dayCount(from: now, to: due, in: calendar)
                guard days <= 60 else { return nil }
                return (evaluation, days)
            }
            .min { $0.1 < $1.1 }

        guard let (evaluation, days) = candidate else { return nil }
        let detail: String
        switch days {
        case ..<0: detail = "Overdue by \(-days) days."
        case 0: detail = "Due today."
        case 1: detail = "Due tomorrow."
        default: detail = "Due in \(days) days."
        }
        return DateBasedItem(planItemID: evaluation.planItemID, title: evaluation.title, detail: detail)
    }
}
