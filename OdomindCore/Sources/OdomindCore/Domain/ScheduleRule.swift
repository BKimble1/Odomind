import Foundation

/// A distance and/or calendar recurrence. At least one side must be present;
/// the catalog validator rejects an empty basis.
public struct RecurrenceBasis: Codable, Hashable, Sendable {
    public var distance: Distance?
    public var time: CalendarInterval?

    public init(distance: Distance? = nil, time: CalendarInterval? = nil) {
        self.distance = distance
        self.time = time
    }

    public var isEmpty: Bool { distance == nil && time == nil }

    public var describesBoth: Bool { distance != nil && time != nil }
}

/// Milestones counted from the vehicle's odometer rather than from the last time
/// the job was done.
///
/// Several manufacturers publish schedules like "inspect at 60,000, 120,000 and
/// 180,000 miles". Doing the job early does not move the next milestone, so this
/// rule deliberately ignores completion history when computing the next due
/// point — that behaviour is the whole reason the case exists.
public struct FixedMilestoneSchedule: Codable, Hashable, Sendable {
    /// Odometer milestones, in any order; the engine sorts them.
    public var distanceMilestones: [Distance]
    /// After the last listed milestone, continue every this-much distance.
    public var repeatEvery: Distance?
    /// Milestones counted from the vehicle's in-service date.
    public var ageMilestones: [CalendarInterval]

    public init(
        distanceMilestones: [Distance] = [],
        repeatEvery: Distance? = nil,
        ageMilestones: [CalendarInterval] = []
    ) {
        self.distanceMilestones = distanceMilestones
        self.repeatEvery = repeatEvery
        self.ageMilestones = ageMilestones
    }

    public var isEmpty: Bool {
        distanceMilestones.isEmpty && ageMilestones.isEmpty && repeatEvery == nil
    }

    var sortedDistanceMilestones: [Distance] {
        distanceMilestones.sorted()
    }
}

/// A service interval the vehicle itself reports, such as an oil-life monitor.
///
/// Odomind cannot read the vehicle, so the owner records what the dash says. The
/// optional maxima are the manufacturer's backstop: if the owner never records
/// the indicator, the backstop still produces a due date.
public struct VehicleIndicatorSchedule: Codable, Hashable, Sendable {
    /// What the message on the dash is called, e.g. "Oil Change Required".
    public var indicatorName: String
    public var maximumDistance: Distance?
    public var maximumTime: CalendarInterval?

    public init(
        indicatorName: String,
        maximumDistance: Distance? = nil,
        maximumTime: CalendarInterval? = nil
    ) {
        self.indicatorName = indicatorName
        self.maximumDistance = maximumDistance
        self.maximumTime = maximumTime
    }
}

/// How often a maintenance task comes due.
///
/// Every rule Odomind supports is one of these cases. Nothing in the app assigns
/// a universal replacement interval to a consumable; tasks whose real answer is
/// "when it is worn" use `conditionCheck`, which schedules inspections without
/// pretending to know a replacement deadline.
public enum ScheduleRule: Hashable, Sendable {
    /// Every `interval` of distance after the last completion.
    case distance(interval: Distance)

    /// Every `interval` of calendar time after the last completion.
    case time(interval: CalendarInterval)

    /// Whichever of the two arrives first after the last completion.
    case distanceOrTime(distance: Distance, time: CalendarInterval)

    /// Fixed points measured from the vehicle, not from the last completion.
    case fixedMilestones(FixedMilestoneSchedule)

    /// Performed once. At least one of the two anchors must be present.
    case oneTime(atDistance: Distance?, atAge: CalendarInterval?)

    /// Recurring inspections with no manufacturer replacement deadline.
    case conditionCheck(every: RecurrenceBasis)

    /// Driven by an indicator the owner records, with an optional backstop.
    case vehicleIndicator(VehicleIndicatorSchedule)

    /// Whether this rule can produce a due point without any completion history.
    ///
    /// Fixed milestones and one-time items are anchored to the vehicle, so they
    /// work from day one. The completion-relative rules need either a logged
    /// service or an explicit "I don't know" acknowledgement first.
    public var isAnchoredToVehicle: Bool {
        switch self {
        case .fixedMilestones, .oneTime:
            return true
        case .distance, .time, .distanceOrTime, .conditionCheck, .vehicleIndicator:
            return false
        }
    }

    /// True for rules that only ever schedule a look, never a replacement.
    public var isInspectionOnly: Bool {
        if case .conditionCheck = self { return true }
        return false
    }

    public var isOneTime: Bool {
        if case .oneTime = self { return true }
        return false
    }

    /// True for the rule shapes that read as "replace every N distance".
    ///
    /// Used to catch a catalog entry that schedules an inspection as though it
    /// were a replacement deadline — the confusion that makes owners replace
    /// parts that were fine and skip ones that were not.
    public var readsAsReplacementInterval: Bool {
        switch self {
        case .distance, .distanceOrTime:
            return true
        case .time, .fixedMilestones, .oneTime, .conditionCheck, .vehicleIndicator:
            return false
        }
    }

    /// Plain-language description used on task cards and in explanations.
    public var summary: String {
        switch self {
        case .distance(let interval):
            return "Every \(interval.amount.formattedWithSeparators) \(interval.unit.localizedName)"
        case .time(let interval):
            return "Every \(interval.description)"
        case .distanceOrTime(let distance, let time):
            return "Every \(distance.amount.formattedWithSeparators) \(distance.unit.localizedName) or \(time.description), whichever comes first"
        case .fixedMilestones(let schedule):
            if let first = schedule.sortedDistanceMilestones.first {
                if let repeatEvery = schedule.repeatEvery {
                    return "At \(first.amount.formattedWithSeparators) \(first.unit.localizedName), then every \(repeatEvery.amount.formattedWithSeparators) \(repeatEvery.unit.localizedName) on the odometer"
                }
                return "At set odometer milestones from \(first.amount.formattedWithSeparators) \(first.unit.localizedName)"
            }
            if let firstAge = schedule.ageMilestones.first {
                return "At \(firstAge.description) of age"
            }
            return "At set milestones"
        case .oneTime(let atDistance, let atAge):
            switch (atDistance, atAge) {
            case (.some(let distance), .some(let age)):
                return "Once, at \(distance.amount.formattedWithSeparators) \(distance.unit.localizedName) or \(age.description)"
            case (.some(let distance), .none):
                return "Once, at \(distance.amount.formattedWithSeparators) \(distance.unit.localizedName)"
            case (.none, .some(let age)):
                return "Once, at \(age.description)"
            case (.none, .none):
                return "Once"
            }
        case .conditionCheck(let basis):
            switch (basis.distance, basis.time) {
            case (.some(let distance), .some(let time)):
                return "Check every \(distance.amount.formattedWithSeparators) \(distance.unit.localizedName) or \(time.description)"
            case (.some(let distance), .none):
                return "Check every \(distance.amount.formattedWithSeparators) \(distance.unit.localizedName)"
            case (.none, .some(let time)):
                return "Check every \(time.description)"
            case (.none, .none):
                return "Check periodically"
            }
        case .vehicleIndicator(let schedule):
            return "When the vehicle shows \(schedule.indicatorName)"
        }
    }

    /// The extra sentence Odomind shows so the owner knows what the rule does
    /// and does not claim.
    public var caveat: String? {
        switch self {
        case .fixedMilestones:
            return "These milestones are counted from the odometer, so doing the work early does not move the next one."
        case .conditionCheck:
            return "This is an inspection interval. Replacement depends on condition, not on a fixed mileage."
        case .vehicleIndicator(let schedule):
            return "Odomind cannot read your vehicle. Record \(schedule.indicatorName) when it appears."
        case .distance, .time, .distanceOrTime, .oneTime:
            return nil
        }
    }

    /// Structural problems that make a rule unusable. Used by the catalog
    /// validator and by the custom-task editor.
    public var validationProblems: [String] {
        switch self {
        case .distance(let interval):
            return interval.amount > 0 ? [] : ["Distance interval must be greater than zero."]
        case .time(let interval):
            return interval.count > 0 ? [] : ["Time interval must be greater than zero."]
        case .distanceOrTime(let distance, let time):
            var problems: [String] = []
            if distance.amount <= 0 { problems.append("Distance interval must be greater than zero.") }
            if time.count <= 0 { problems.append("Time interval must be greater than zero.") }
            return problems
        case .fixedMilestones(let schedule):
            var problems: [String] = []
            if schedule.isEmpty { problems.append("A milestone schedule needs at least one milestone.") }
            if schedule.distanceMilestones.contains(where: { $0.amount <= 0 }) {
                problems.append("Milestones must be greater than zero.")
            }
            if let repeatEvery = schedule.repeatEvery, repeatEvery.amount <= 0 {
                problems.append("Repeat interval must be greater than zero.")
            }
            return problems
        case .oneTime(let atDistance, let atAge):
            if atDistance == nil && atAge == nil {
                return ["A one-time task needs a distance or an age."]
            }
            var problems: [String] = []
            if let atDistance, atDistance.amount <= 0 { problems.append("Distance must be greater than zero.") }
            if let atAge, atAge.count <= 0 { problems.append("Age must be greater than zero.") }
            return problems
        case .conditionCheck(let basis):
            if basis.isEmpty { return ["A condition check needs a distance or a time interval."] }
            var problems: [String] = []
            if let distance = basis.distance, distance.amount <= 0 {
                problems.append("Check distance must be greater than zero.")
            }
            if let time = basis.time, time.count <= 0 {
                problems.append("Check interval must be greater than zero.")
            }
            return problems
        case .vehicleIndicator(let schedule):
            return schedule.indicatorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? ["An indicator rule needs the name of the message shown on the dash."]
                : []
        }
    }
}

extension ScheduleRule: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case distance
        case time
        case milestones
        case indicator
    }

    private enum RuleType: String, Codable {
        case distance
        case time
        case distanceOrTime
        case fixedMilestones
        case oneTime
        case conditionCheck
        case vehicleIndicator
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(RuleType.self, forKey: .type)
        switch type {
        case .distance:
            self = .distance(interval: try container.decode(Distance.self, forKey: .distance))
        case .time:
            self = .time(interval: try container.decode(CalendarInterval.self, forKey: .time))
        case .distanceOrTime:
            self = .distanceOrTime(
                distance: try container.decode(Distance.self, forKey: .distance),
                time: try container.decode(CalendarInterval.self, forKey: .time)
            )
        case .fixedMilestones:
            self = .fixedMilestones(try container.decode(FixedMilestoneSchedule.self, forKey: .milestones))
        case .oneTime:
            self = .oneTime(
                atDistance: try container.decodeIfPresent(Distance.self, forKey: .distance),
                atAge: try container.decodeIfPresent(CalendarInterval.self, forKey: .time)
            )
        case .conditionCheck:
            let basis = RecurrenceBasis(
                distance: try container.decodeIfPresent(Distance.self, forKey: .distance),
                time: try container.decodeIfPresent(CalendarInterval.self, forKey: .time)
            )
            self = .conditionCheck(every: basis)
        case .vehicleIndicator:
            self = .vehicleIndicator(try container.decode(VehicleIndicatorSchedule.self, forKey: .indicator))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .distance(let interval):
            try container.encode(RuleType.distance, forKey: .type)
            try container.encode(interval, forKey: .distance)
        case .time(let interval):
            try container.encode(RuleType.time, forKey: .type)
            try container.encode(interval, forKey: .time)
        case .distanceOrTime(let distance, let time):
            try container.encode(RuleType.distanceOrTime, forKey: .type)
            try container.encode(distance, forKey: .distance)
            try container.encode(time, forKey: .time)
        case .fixedMilestones(let schedule):
            try container.encode(RuleType.fixedMilestones, forKey: .type)
            try container.encode(schedule, forKey: .milestones)
        case .oneTime(let atDistance, let atAge):
            try container.encode(RuleType.oneTime, forKey: .type)
            try container.encodeIfPresent(atDistance, forKey: .distance)
            try container.encodeIfPresent(atAge, forKey: .time)
        case .conditionCheck(let basis):
            try container.encode(RuleType.conditionCheck, forKey: .type)
            try container.encodeIfPresent(basis.distance, forKey: .distance)
            try container.encodeIfPresent(basis.time, forKey: .time)
        case .vehicleIndicator(let schedule):
            try container.encode(RuleType.vehicleIndicator, forKey: .type)
            try container.encode(schedule, forKey: .indicator)
        }
    }
}

extension Int {
    /// Thousands separators without pulling a locale-aware formatter into the
    /// portable core. The app layer formats for display; this is for the plain
    /// summaries the engine produces.
    var formattedWithSeparators: String {
        let isNegative = self < 0
        var digits = String(abs(self))
        var grouped: [String] = []
        while digits.count > 3 {
            let index = digits.index(digits.endIndex, offsetBy: -3)
            grouped.insert(String(digits[index...]), at: 0)
            digits = String(digits[..<index])
        }
        grouped.insert(digits, at: 0)
        return (isNegative ? "-" : "") + grouped.joined(separator: ",")
    }
}
