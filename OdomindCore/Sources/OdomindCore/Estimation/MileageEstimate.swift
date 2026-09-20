import Foundation

public enum EstimateConfidence: String, Codable, Sendable, CaseIterable, Hashable, Comparable {
    case low
    case medium
    case high

    private var rank: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        }
    }

    public static func < (lhs: EstimateConfidence, rhs: EstimateConfidence) -> Bool {
        lhs.rank < rhs.rank
    }

    public var displayName: String {
        switch self {
        case .low: return "Rough"
        case .medium: return "Fair"
        case .high: return "Good"
        }
    }
}

public enum EstimateBasis: Hashable, Sendable {
    /// Derived from the owner's own dated odometer readings.
    case recordedReadings(count: Int, spanDays: Int)
    /// The owner told Odomind roughly how far they drive.
    case ownerDeclaredTypicalDistance
}

/// Why Odomind will not estimate.
///
/// Surfaced verbatim in the UI so "no estimate" is never a silent absence.
public enum EstimateUnavailableReason: Hashable, Sendable {
    case noReadings
    case singleReading
    case spanTooShort(days: Int, required: Int)
    case readingsTooStale(daysSinceLatest: Int, limit: Int)
    case noDistanceCovered

    public var message: String {
        switch self {
        case .noReadings:
            return "Odomind has no odometer readings for this vehicle yet."
        case .singleReading:
            return "One reading is not enough to estimate how far you drive. Add another when you next check."
        case .spanTooShort(let days, let required):
            return "Your readings only cover \(days) day\(days == 1 ? "" : "s"). Odomind needs at least \(required) to estimate."
        case .readingsTooStale(let daysSinceLatest, _):
            return "Your last reading is \(daysSinceLatest) days old. Update your mileage for an estimate."
        case .noDistanceCovered:
            return "Your readings show no distance covered, so there is nothing to project."
        }
    }
}

/// A projection of how far the vehicle is driven, used only for estimated dates.
///
/// An estimate never becomes an odometer reading. Nothing derived from one is
/// allowed to mark a task overdue on distance; the engine only uses it to say
/// "estimated to be due around <date>".
public struct MileageEstimate: Hashable, Sendable {
    public var distancePerDay: Double
    public var unit: DistanceUnit
    public var confidence: EstimateConfidence
    public var basis: EstimateBasis
    /// The reading the projection starts from.
    public var referenceOdometer: Distance
    public var referenceDate: Date
    public var computedOn: Date

    public init(
        distancePerDay: Double,
        unit: DistanceUnit,
        confidence: EstimateConfidence,
        basis: EstimateBasis,
        referenceOdometer: Distance,
        referenceDate: Date,
        computedOn: Date
    ) {
        self.distancePerDay = distancePerDay
        self.unit = unit
        self.confidence = confidence
        self.basis = basis
        self.referenceOdometer = referenceOdometer
        self.referenceDate = referenceDate
        self.computedOn = computedOn
    }

    /// Approximate date the odometer reaches `target`, or `nil` when the vehicle
    /// is not being driven far enough for the projection to mean anything.
    public func projectedDate(reaching target: Distance, calendar: Calendar) -> Date? {
        guard distancePerDay > 0.05 else { return nil }
        let remaining = (target - referenceOdometer).converted(to: unit)
        let days = Double(remaining.amount) / distancePerDay
        guard days.isFinite, abs(days) < 36_500 else { return nil }
        return calendar.date(byAdding: .day, value: Int(days.rounded()), to: referenceDate)
    }

    /// Plain-language explanation of where the number came from.
    public var explanation: String {
        let rate = distancePerDay * 30
        let rounded = Int(rate.rounded())
        switch basis {
        case .recordedReadings(let count, let spanDays):
            return "Based on \(count) readings over \(spanDays) days, about \(rounded.formattedWithSeparators) \(unit.localizedName) a month."
        case .ownerDeclaredTypicalDistance:
            return "Based on the typical distance you entered, about \(rounded.formattedWithSeparators) \(unit.localizedName) a month."
        }
    }
}

public enum MileageEstimateResult: Hashable, Sendable {
    case available(MileageEstimate)
    case unavailable(EstimateUnavailableReason)

    public var estimate: MileageEstimate? {
        if case .available(let estimate) = self { return estimate }
        return nil
    }

    public var unavailableReason: EstimateUnavailableReason? {
        if case .unavailable(let reason) = self { return reason }
        return nil
    }
}
