import Foundation

/// Which side of a rule is driving the next due point.
public enum DueBasis: String, Sendable, Hashable, CaseIterable {
    case distance
    case date
    case both
    case indicator
    case none
}

/// The bucket a task falls into on the Today screen.
///
/// `historyUnknown` and `needsSetup` are separate states, not a flavour of
/// upcoming. A task Odomind cannot schedule is never shown as safe.
public enum DueState: String, Sendable, Hashable, CaseIterable {
    case overdue
    case dueSoon
    case upcoming
    /// The owner said they do not know when this was last done.
    case historyUnknown
    /// Odomind is missing something it needs: a reading, a baseline, or a
    /// configuration answer.
    case needsSetup
    /// A one-time task that has been done.
    case completed
    /// Filtered out by the vehicle's configuration.
    case notApplicable

    /// Display order for grouped lists.
    public var sortRank: Int {
        switch self {
        case .overdue: return 0
        case .dueSoon: return 1
        case .upcoming: return 2
        case .historyUnknown: return 3
        case .needsSetup: return 4
        case .completed: return 5
        case .notApplicable: return 6
        }
    }

    public var displayName: String {
        switch self {
        case .overdue: return "Overdue"
        case .dueSoon: return "Due soon"
        case .upcoming: return "Upcoming"
        case .historyUnknown: return "History unknown"
        case .needsSetup: return "Needs setup"
        case .completed: return "Completed"
        case .notApplicable: return "Not applicable"
        }
    }

    /// Whether this state represents scheduled work with a known deadline.
    public var isScheduled: Bool {
        switch self {
        case .overdue, .dueSoon, .upcoming: return true
        case .historyUnknown, .needsSetup, .completed, .notApplicable: return false
        }
    }
}

/// A plain-language factor behind an evaluation.
///
/// The UI renders these instead of inventing its own copy, so what the engine
/// computed and what the owner reads can never drift apart.
public enum EvaluationReason: Hashable, Sendable {
    case noCompletionRecorded
    case ownerDoesNotKnowHistory
    case noOdometerReading
    case inServiceDateUnknown
    case configurationQuestionOpen(ConfigurationQuestion)
    case notApplicable(String)

    case overdueByDistance(Distance)
    case overdueByDays(Int)
    case dueInDistance(Distance)
    case dueInDays(Int)

    case fixedMilestoneFromOdometer(Distance)
    case milestoneAlreadyPassed(Distance)
    case inspectionIntervalOnly
    case indicatorNotReported(String)
    case indicatorBackstop

    /// The recorded odometer has not reached the due point, but a projection
    /// suggests it will soon. Never an overdue claim.
    case estimatedCrossing(on: Date, confidence: EstimateConfidence)
    case estimateUnavailable(EstimateUnavailableReason)
    case snoozedUntil(Date)
    case oneTimeCompleted(Date)

    public var message: String {
        switch self {
        case .noCompletionRecorded:
            return "No completion recorded yet, so Odomind cannot work out when this is next due."
        case .ownerDoesNotKnowHistory:
            return "You said you do not know when this was last done."
        case .noOdometerReading:
            return "Add an odometer reading to schedule this."
        case .inServiceDateUnknown:
            return "Add the date this vehicle entered service to schedule age-based milestones."
        case .configurationQuestionOpen(let question):
            return question.rationale
        case .notApplicable(let reason):
            return reason
        case .overdueByDistance(let distance):
            return "Overdue by \(distance.amount.formattedWithSeparators) \(distance.unit.localizedName)."
        case .overdueByDays(let days):
            return "Overdue by \(days) day\(days == 1 ? "" : "s")."
        case .dueInDistance(let distance):
            return "Due in \(distance.amount.formattedWithSeparators) \(distance.unit.localizedName)."
        case .dueInDays(let days):
            return days == 0 ? "Due today." : "Due in \(days) day\(days == 1 ? "" : "s")."
        case .fixedMilestoneFromOdometer(let distance):
            return "Next milestone at \(distance.amount.formattedWithSeparators) \(distance.unit.localizedName) on the odometer."
        case .milestoneAlreadyPassed(let distance):
            return "The \(distance.amount.formattedWithSeparators) \(distance.unit.localizedName) milestone has passed without a record."
        case .inspectionIntervalOnly:
            return "This is an inspection interval. Replacement depends on condition."
        case .indicatorNotReported(let name):
            return "Watching for \(name). Record it when your vehicle shows it."
        case .indicatorBackstop:
            return "Using the manufacturer's maximum interval because the indicator has not been recorded."
        case .estimatedCrossing(let date, let confidence):
            return "Estimated to reach this point around \(EvaluationReason.dateText(date)) (\(confidence.displayName.lowercased()) estimate). Update your mileage to confirm."
        case .estimateUnavailable(let reason):
            return reason.message
        case .snoozedUntil(let date):
            return "Snoozed until \(EvaluationReason.dateText(date)). Reminders are paused; the due date has not changed."
        case .oneTimeCompleted(let date):
            return "Completed on \(EvaluationReason.dateText(date))."
        }
    }

    /// ISO-style date used only inside engine-produced strings. The app layer
    /// re-formats dates for display with the owner's locale.
    static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

/// The result of evaluating one plan item.
public struct ScheduleEvaluation: Hashable, Sendable, Identifiable {
    public var id: UUID { planItemID }

    public var planItemID: UUID
    public var vehicleID: UUID
    public var definitionID: String
    public var title: String
    public var state: DueState
    public var basis: DueBasis

    /// The odometer value at which the task is next due, on the cumulative
    /// scale.
    public var nextDueOdometer: Distance?
    /// A deadline Odomind is confident about, from a calendar rule. Never
    /// derived from an estimate.
    public var nextDueDate: Date?
    /// A projection of when a distance-based due point will be reached. Always
    /// labelled as estimated in the UI.
    public var estimatedDueDate: Date?
    public var estimateConfidence: EstimateConfidence?

    /// Positive when the due point is still ahead, negative when passed.
    public var distanceRemaining: Distance?
    public var daysRemaining: Int?

    public var lastCompletedOn: Date?
    public var lastCompletedOdometer: Distance?

    public var isSnoozed: Bool
    public var snoozedUntil: Date?
    public var reasons: [EvaluationReason]

    public init(
        planItemID: UUID,
        vehicleID: UUID,
        definitionID: String,
        title: String,
        state: DueState,
        basis: DueBasis = .none,
        nextDueOdometer: Distance? = nil,
        nextDueDate: Date? = nil,
        estimatedDueDate: Date? = nil,
        estimateConfidence: EstimateConfidence? = nil,
        distanceRemaining: Distance? = nil,
        daysRemaining: Int? = nil,
        lastCompletedOn: Date? = nil,
        lastCompletedOdometer: Distance? = nil,
        isSnoozed: Bool = false,
        snoozedUntil: Date? = nil,
        reasons: [EvaluationReason] = []
    ) {
        self.planItemID = planItemID
        self.vehicleID = vehicleID
        self.definitionID = definitionID
        self.title = title
        self.state = state
        self.basis = basis
        self.nextDueOdometer = nextDueOdometer
        self.nextDueDate = nextDueDate
        self.estimatedDueDate = estimatedDueDate
        self.estimateConfidence = estimateConfidence
        self.distanceRemaining = distanceRemaining
        self.daysRemaining = daysRemaining
        self.lastCompletedOn = lastCompletedOn
        self.lastCompletedOdometer = lastCompletedOdometer
        self.isSnoozed = isSnoozed
        self.snoozedUntil = snoozedUntil
        self.reasons = reasons
    }

    /// True when the due point was reached on a recorded odometer reading or a
    /// real calendar deadline — never on a projection.
    public var isConfirmedOverdue: Bool { state == .overdue }

    /// Sort key for the Today list: most urgent first, then soonest.
    public var urgencyKey: (Int, Int) {
        let stateRank = state.sortRank
        let within: Int
        if let daysRemaining {
            within = daysRemaining
        } else if let distanceRemaining {
            // Scale distance into a comparable magnitude so that a task due in
            // 200 miles sorts ahead of one due in 5,000.
            within = distanceRemaining.converted(to: .miles).amount
        } else {
            within = Int.max
        }
        return (stateRank, within)
    }
}


/// Evaluations sharing a due state, in urgency order.
///
/// A named type rather than a tuple so it can be identified directly in a list.
public struct DueGroup: Identifiable, Hashable, Sendable {
    public var id: DueState { state }
    public var state: DueState
    public var items: [ScheduleEvaluation]

    public init(state: DueState, items: [ScheduleEvaluation]) {
        self.state = state
        self.items = items
    }
}
