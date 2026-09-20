import Foundation

/// The deterministic maintenance scheduler.
///
/// Every function here is pure: given the same `ScheduleContext` and plan item
/// it always returns the same evaluation. There is no clock, no locale, no
/// storage and no randomness, which is what makes the boundary cases in
/// `ScheduleEngineTests` meaningful.
public enum ScheduleEngine {

    // MARK: - Public entry points

    /// Evaluates one plan item.
    ///
    /// - Parameter definition: the catalog definition, when the task came from
    ///   the catalog. Supplying it lets the engine retire a task whose
    ///   applicability no longer matches the vehicle's configuration.
    public static func evaluate(
        _ item: MaintenancePlanItem,
        definition: MaintenanceTaskDefinition? = nil,
        in context: ScheduleContext
    ) -> ScheduleEvaluation {
        let completion = context.latestCompletion(of: item.definitionID)
        var evaluation = ScheduleEvaluation(
            planItemID: item.id,
            vehicleID: item.vehicleID,
            definitionID: item.definitionID,
            title: item.title,
            state: .needsSetup,
            lastCompletedOn: completion?.performedOn,
            lastCompletedOdometer: completion?.cumulativeOdometer
        )

        if let snoozedUntil = item.snoozedUntil, snoozedUntil > context.asOf {
            evaluation.isSnoozed = true
            evaluation.snoozedUntil = snoozedUntil
        }

        guard item.isEnabled else {
            evaluation.state = .notApplicable
            evaluation.reasons = [.notApplicable("Turned off for this vehicle.")]
            return evaluation
        }

        if let definition {
            switch definition.applicability.evaluate(for: context.vehicle.configuration) {
            case .applies:
                break
            case .doesNotApply(let reason):
                evaluation.state = .notApplicable
                evaluation.reasons = [.notApplicable(reason)]
                return evaluation
            case .needsConfirmation(let question, _):
                evaluation.state = .needsSetup
                evaluation.reasons = [.configurationQuestionOpen(question)]
                return evaluation
            }
        }

        guard let rule = item.effectiveRule else {
            evaluation.state = .needsSetup
            evaluation.reasons = [.noCompletionRecorded]
            return evaluation
        }

        var outcome: Outcome
        switch rule {
        case .distance(let interval):
            outcome = completionRelative(
                distanceInterval: interval,
                timeInterval: nil,
                item: item,
                completion: completion,
                context: context
            )
        case .time(let interval):
            outcome = completionRelative(
                distanceInterval: nil,
                timeInterval: interval,
                item: item,
                completion: completion,
                context: context
            )
        case .distanceOrTime(let distance, let time):
            outcome = completionRelative(
                distanceInterval: distance,
                timeInterval: time,
                item: item,
                completion: completion,
                context: context
            )
        case .conditionCheck(let basis):
            outcome = completionRelative(
                distanceInterval: basis.distance,
                timeInterval: basis.time,
                item: item,
                completion: completion,
                context: context
            )
            outcome.reasons.insert(.inspectionIntervalOnly, at: 0)
        case .fixedMilestones(let schedule):
            outcome = fixedMilestones(schedule: schedule, item: item, context: context)
        case .oneTime(let atDistance, let atAge):
            outcome = oneTime(
                atDistance: atDistance,
                atAge: atAge,
                item: item,
                completion: completion,
                context: context
            )
        case .vehicleIndicator(let schedule):
            outcome = vehicleIndicator(
                schedule: schedule,
                item: item,
                completion: completion,
                context: context
            )
        }

        evaluation.state = outcome.state
        evaluation.basis = outcome.basis
        evaluation.nextDueOdometer = outcome.dueOdometer
        evaluation.nextDueDate = outcome.dueDate
        evaluation.estimatedDueDate = outcome.estimatedDate
        evaluation.estimateConfidence = outcome.estimatedDate == nil ? nil : context.estimate?.confidence
        evaluation.distanceRemaining = outcome.distanceRemaining
        evaluation.daysRemaining = outcome.daysRemaining
        evaluation.reasons = outcome.reasons

        if evaluation.isSnoozed, let snoozedUntil = evaluation.snoozedUntil {
            // Snoozing pauses reminders. It deliberately does not change the due
            // state, so overdue work never looks done.
            evaluation.reasons.append(.snoozedUntil(snoozedUntil))
        }

        return evaluation
    }

    /// Evaluates a whole plan and returns the results most urgent first.
    public static func evaluateAll(
        _ items: [MaintenancePlanItem],
        definitions: [String: MaintenanceTaskDefinition] = [:],
        in context: ScheduleContext
    ) -> [ScheduleEvaluation] {
        items
            .map { evaluate($0, definition: definitions[$0.definitionID], in: context) }
            .sorted { lhs, rhs in
                let left = lhs.urgencyKey
                let right = rhs.urgencyKey
                if left.0 != right.0 { return left.0 < right.0 }
                if left.1 != right.1 { return left.1 < right.1 }
                return lhs.title.lowercased() < rhs.title.lowercased()
            }
    }

    /// Groups evaluations by state, preserving urgency order inside each group.
    public static func grouped(
        _ evaluations: [ScheduleEvaluation]
    ) -> [(state: DueState, items: [ScheduleEvaluation])] {
        var buckets: [DueState: [ScheduleEvaluation]] = [:]
        for evaluation in evaluations {
            buckets[evaluation.state, default: []].append(evaluation)
        }
        return DueState.allCases
            .sorted { $0.sortRank < $1.sortRank }
            .compactMap { state in
                guard let items = buckets[state], !items.isEmpty else { return nil }
                return (state, items)
            }
    }

    // MARK: - Internal types

    struct Outcome {
        var state: DueState = .needsSetup
        var basis: DueBasis = .none
        var dueOdometer: Distance?
        var dueDate: Date?
        var estimatedDate: Date?
        var distanceRemaining: Distance?
        var daysRemaining: Int?
        var reasons: [EvaluationReason] = []
    }

    /// One side of a rule: either the distance leg or the calendar leg.
    /// `state == nil` means the leg could not be resolved at all.
    private struct Leg {
        var state: DueState?
        var dueOdometer: Distance?
        var dueDate: Date?
        var remainingDistance: Distance?
        var remainingDays: Int?
        var estimatedDate: Date?
        var reasons: [EvaluationReason] = []
    }

    // MARK: - Completion-relative rules

    private static func completionRelative(
        distanceInterval: Distance?,
        timeInterval: CalendarInterval?,
        item: MaintenancePlanItem,
        completion: ServiceCompletion?,
        context: ScheduleContext
    ) -> Outcome {
        let baselineOdometer = distanceBaseline(item: item, completion: completion, context: context)
        let baselineDate = dateBaseline(item: item, completion: completion)

        var distanceSide: Leg?
        if let distanceInterval {
            if let baselineOdometer {
                distanceSide = makeDistanceLeg(
                    dueOdometer: baselineOdometer + distanceInterval,
                    item: item,
                    context: context
                )
            } else {
                // The distance half cannot run without a starting odometer.
                // When the owner has no readings at all, say so — a reading is
                // what unlocks it. When they do have readings, the missing
                // piece is the completion history, which `unresolved` explains.
                distanceSide = context.ledger.latestCumulative == nil
                    ? Leg(state: nil, reasons: [.noOdometerReading])
                    : Leg(state: nil)
            }
        }

        var timeSide: Leg?
        if let timeInterval {
            if let baselineDate, let due = timeInterval.advancing(baselineDate, in: context.calendar) {
                timeSide = makeCalendarLeg(dueDate: due, item: item, context: context)
            } else {
                timeSide = Leg(state: nil)
            }
        }

        if resolvedLegCount(distanceSide, timeSide) == 0 {
            return unresolved(
                item: item,
                legs: [distanceSide, timeSide],
                hasBaseline: baselineOdometer != nil || baselineDate != nil,
                context: context
            )
        }

        return combine(distanceSide: distanceSide, timeSide: timeSide)
    }

    /// The odometer value a completion-relative distance rule counts from.
    private static func distanceBaseline(
        item: MaintenancePlanItem,
        completion: ServiceCompletion?,
        context: ScheduleContext
    ) -> Distance? {
        if let recorded = completion?.cumulativeOdometer {
            return recorded
        }
        if case .declared(let date, let odometer) = item.baseline, let odometer {
            let anchor = date ?? context.vehicle.createdAt
            return context.ledger.cumulative(rawValue: odometer, on: anchor)
        }
        return nil
    }

    /// The date a completion-relative calendar rule counts from.
    private static func dateBaseline(
        item: MaintenancePlanItem,
        completion: ServiceCompletion?
    ) -> Date? {
        if let performed = completion?.performedOn {
            return performed
        }
        if case .declared(let date, _) = item.baseline, let date {
            return date
        }
        return nil
    }

    private static func resolvedLegCount(_ legs: Leg?...) -> Int {
        legs.compactMap { $0 }.filter { $0.state != nil }.count
    }

    /// Builds the outcome for a rule Odomind cannot schedule yet.
    ///
    /// The distinction between "you told us you don't know" and "we still need
    /// something" is preserved, because an owner who answered deserves a
    /// different screen from one who has not been asked.
    private static func unresolved(
        item: MaintenancePlanItem,
        legs: [Leg?],
        hasBaseline: Bool,
        context: ScheduleContext
    ) -> Outcome {
        var outcome = Outcome()
        if case .unknownToOwner = item.baseline {
            outcome.state = .historyUnknown
            outcome.reasons.append(.ownerDoesNotKnowHistory)
        } else {
            outcome.state = .needsSetup
            // Only claim there is no completion when there really is none. A
            // service logged without a reading is a different problem and gets
            // a different explanation.
            if !hasBaseline {
                outcome.reasons.append(.noCompletionRecorded)
            }
        }
        for leg in legs.compactMap({ $0 }) {
            outcome.reasons.append(contentsOf: leg.reasons)
        }
        if outcome.reasons.isEmpty {
            outcome.reasons.append(
                context.ledger.latestCumulative == nil ? .noOdometerReading : .noCompletionRecorded
            )
        }
        return outcome
    }

    // MARK: - Legs

    private static func makeDistanceLeg(
        dueOdometer: Distance,
        item: MaintenancePlanItem,
        context: ScheduleContext
    ) -> Leg {
        var leg = Leg()
        leg.dueOdometer = dueOdometer

        guard let current = context.ledger.latestCumulative else {
            leg.state = nil
            leg.reasons.append(.noOdometerReading)
            return leg
        }

        let remaining = (dueOdometer - current).converted(to: context.vehicle.displayUnit)
        leg.remainingDistance = remaining

        if remaining.amount <= 0 {
            leg.state = .overdue
            leg.reasons.append(.overdueByDistance(remaining.magnitude))
        } else {
            if let threshold = item.dueSoonThreshold.distance, remaining <= threshold {
                leg.state = .dueSoon
            } else {
                leg.state = .upcoming
            }
            leg.reasons.append(.dueInDistance(remaining))
        }

        // A projection can suggest the odometer will reach the due point soon,
        // but it can never make the task overdue: only a reading the owner
        // actually took does that.
        if let estimate = context.estimate,
           let projected = estimate.projectedDate(reaching: dueOdometer, calendar: context.calendar) {
            leg.estimatedDate = projected
            if leg.state == .upcoming {
                let daysAway = DateSupport.dayCount(from: context.asOf, to: projected, in: context.calendar)
                if daysAway <= (item.dueSoonThreshold.days ?? 0) {
                    leg.state = .dueSoon
                    leg.reasons.append(.estimatedCrossing(on: projected, confidence: estimate.confidence))
                }
            } else if leg.state == .dueSoon {
                leg.reasons.append(.estimatedCrossing(on: projected, confidence: estimate.confidence))
            }
        } else if context.estimate == nil, let reason = context.estimateUnavailableReason {
            leg.reasons.append(.estimateUnavailable(reason))
        }

        return leg
    }

    private static func makeCalendarLeg(
        dueDate: Date,
        item: MaintenancePlanItem,
        context: ScheduleContext
    ) -> Leg {
        var leg = Leg()
        leg.dueDate = dueDate

        let days = DateSupport.dayCount(from: context.asOf, to: dueDate, in: context.calendar)
        leg.remainingDays = days

        if days < 0 {
            leg.state = .overdue
            leg.reasons.append(.overdueByDays(-days))
        } else {
            if let window = item.dueSoonThreshold.days, days <= window {
                leg.state = .dueSoon
            } else {
                leg.state = .upcoming
            }
            leg.reasons.append(.dueInDays(days))
        }
        return leg
    }

    /// Merges two legs, taking whichever is more urgent.
    private static func combine(distanceSide: Leg?, timeSide: Leg?) -> Outcome {
        var outcome = Outcome()
        let distanceState = distanceSide?.state
        let timeState = timeSide?.state

        switch (distanceState, timeState) {
        case (.some(let lhs), .some(let rhs)):
            outcome.state = lhs.sortRank <= rhs.sortRank ? lhs : rhs
            outcome.basis = lhs == rhs ? .both : (lhs.sortRank <= rhs.sortRank ? .distance : .date)
        case (.some(let lhs), .none):
            outcome.state = lhs
            outcome.basis = .distance
        case (.none, .some(let rhs)):
            outcome.state = rhs
            outcome.basis = .date
        case (.none, .none):
            outcome.state = .needsSetup
            outcome.basis = .none
        }

        outcome.dueOdometer = distanceSide?.dueOdometer
        outcome.dueDate = timeSide?.dueDate
        outcome.estimatedDate = distanceSide?.estimatedDate
        outcome.distanceRemaining = distanceSide?.remainingDistance
        outcome.daysRemaining = timeSide?.remainingDays

        if let distanceSide { outcome.reasons.append(contentsOf: distanceSide.reasons) }
        if let timeSide { outcome.reasons.append(contentsOf: timeSide.reasons) }
        return outcome
    }

    // MARK: - Fixed milestones

    private static func fixedMilestones(
        schedule: FixedMilestoneSchedule,
        item: MaintenancePlanItem,
        context: ScheduleContext
    ) -> Outcome {
        var distanceSide: Leg?
        if !schedule.distanceMilestones.isEmpty || schedule.repeatEvery != nil {
            if let current = context.ledger.latestCumulative {
                let tolerance = item.dueSoonThreshold.distance ?? Distance(0, context.vehicle.displayUnit)
                let completions = context.allCompletions(of: item.definitionID)
                if let next = nextUnmetMilestone(
                    schedule: schedule,
                    current: current,
                    tolerance: tolerance,
                    completions: completions
                ) {
                    var leg = makeDistanceLeg(dueOdometer: next, item: item, context: context)
                    if next <= current {
                        leg.reasons.insert(.milestoneAlreadyPassed(next), at: 0)
                    } else {
                        leg.reasons.insert(.fixedMilestoneFromOdometer(next), at: 0)
                    }
                    distanceSide = leg
                } else {
                    var finished = Outcome()
                    finished.state = .completed
                    finished.reasons = [
                        .notApplicable("Every published milestone for this task has been recorded.")
                    ]
                    return finished
                }
            } else {
                distanceSide = Leg(state: nil, reasons: [.noOdometerReading])
            }
        }

        var timeSide: Leg?
        if !schedule.ageMilestones.isEmpty {
            if let inService = context.vehicle.inServiceOn {
                let completions = context.allCompletions(of: item.definitionID)
                if let dueDate = nextUnmetAgeMilestone(
                    schedule: schedule,
                    inServiceOn: inService,
                    completions: completions,
                    toleranceDays: item.dueSoonThreshold.days ?? 0,
                    calendar: context.calendar
                ) {
                    timeSide = makeCalendarLeg(dueDate: dueDate, item: item, context: context)
                }
            } else {
                timeSide = Leg(state: nil, reasons: [.inServiceDateUnknown])
            }
        }

        if resolvedLegCount(distanceSide, timeSide) == 0 {
            var outcome = Outcome()
            outcome.state = .needsSetup
            for leg in [distanceSide, timeSide].compactMap({ $0 }) {
                outcome.reasons.append(contentsOf: leg.reasons)
            }
            if outcome.reasons.isEmpty { outcome.reasons.append(.noOdometerReading) }
            return outcome
        }

        return combine(distanceSide: distanceSide, timeSide: timeSide)
    }

    /// The first milestone with no completion recorded at or after it.
    ///
    /// A completion counts towards a milestone when it was logged within the
    /// due-soon window before that milestone, so the 60,000 service done at
    /// 59,700 counts. Work done far earlier does not move the milestone, which
    /// is the whole point of a fixed schedule.
    static func nextUnmetMilestone(
        schedule: FixedMilestoneSchedule,
        current: Distance,
        tolerance: Distance,
        completions: [ServiceCompletion]
    ) -> Distance? {
        var milestones = schedule.sortedDistanceMilestones

        if let repeatEvery = schedule.repeatEvery, repeatEvery.amount > 0 {
            if milestones.isEmpty { milestones.append(repeatEvery) }
            var cursor = milestones[milestones.count - 1]
            let ceiling = current + repeatEvery
            var generated = 0
            while cursor < ceiling, generated < 2_000 {
                cursor = cursor + repeatEvery
                milestones.append(cursor)
                generated += 1
            }
        }

        let recorded = completions.compactMap { $0.cumulativeOdometer }
        for milestone in milestones {
            let satisfiedFrom = milestone - tolerance
            let isSatisfied = recorded.contains { $0 >= satisfiedFrom }
            if !isSatisfied { return milestone }
        }
        return nil
    }

    static func nextUnmetAgeMilestone(
        schedule: FixedMilestoneSchedule,
        inServiceOn: Date,
        completions: [ServiceCompletion],
        toleranceDays: Int,
        calendar: Calendar
    ) -> Date? {
        let dates = schedule.ageMilestones
            .compactMap { $0.advancing(inServiceOn, in: calendar) }
            .sorted()
        for date in dates {
            let earliestQualifying = calendar.date(
                byAdding: .day,
                value: -max(toleranceDays, 0),
                to: calendar.startOfDay(for: date)
            ) ?? calendar.startOfDay(for: date)
            let isSatisfied = completions.contains { $0.performedOn >= earliestQualifying }
            if !isSatisfied { return date }
        }
        return nil
    }

    // MARK: - One-time

    private static func oneTime(
        atDistance: Distance?,
        atAge: CalendarInterval?,
        item: MaintenancePlanItem,
        completion: ServiceCompletion?,
        context: ScheduleContext
    ) -> Outcome {
        if let completion {
            var done = Outcome()
            done.state = .completed
            done.reasons = [.oneTimeCompleted(completion.performedOn)]
            return done
        }

        var distanceSide: Leg?
        if let atDistance {
            if context.ledger.latestCumulative != nil {
                distanceSide = makeDistanceLeg(dueOdometer: atDistance, item: item, context: context)
            } else {
                distanceSide = Leg(state: nil, reasons: [.noOdometerReading])
            }
        }

        var timeSide: Leg?
        if let atAge {
            if let inService = context.vehicle.inServiceOn,
               let due = atAge.advancing(inService, in: context.calendar) {
                timeSide = makeCalendarLeg(dueDate: due, item: item, context: context)
            } else {
                timeSide = Leg(state: nil, reasons: [.inServiceDateUnknown])
            }
        }

        if resolvedLegCount(distanceSide, timeSide) == 0 {
            var outcome = Outcome()
            outcome.state = .needsSetup
            for leg in [distanceSide, timeSide].compactMap({ $0 }) {
                outcome.reasons.append(contentsOf: leg.reasons)
            }
            if outcome.reasons.isEmpty { outcome.reasons.append(.noOdometerReading) }
            return outcome
        }

        return combine(distanceSide: distanceSide, timeSide: timeSide)
    }

    // MARK: - Vehicle-reported indicator

    private static func vehicleIndicator(
        schedule: VehicleIndicatorSchedule,
        item: MaintenancePlanItem,
        completion: ServiceCompletion?,
        context: ScheduleContext
    ) -> Outcome {
        var outcome = completionRelative(
            distanceInterval: schedule.maximumDistance,
            timeInterval: schedule.maximumTime,
            item: item,
            completion: completion,
            context: context
        )

        let hasBackstop = schedule.maximumDistance != nil || schedule.maximumTime != nil

        if !hasBackstop, outcome.state == .needsSetup || outcome.state == .historyUnknown {
            // Nothing to schedule against, but this is not a setup problem: the
            // owner simply has not seen the message on the dash yet.
            var watching = Outcome()
            watching.state = .upcoming
            watching.basis = .indicator
            watching.reasons = [.indicatorNotReported(schedule.indicatorName)]
            return watching
        }

        if outcome.basis == .none { outcome.basis = .indicator }
        outcome.reasons.insert(.indicatorNotReported(schedule.indicatorName), at: 0)
        if hasBackstop {
            outcome.reasons.insert(.indicatorBackstop, at: 1)
        }
        return outcome
    }
}
