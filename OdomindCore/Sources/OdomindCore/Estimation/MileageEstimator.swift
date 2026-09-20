import Foundation

/// Projects how far a vehicle is driven from its recorded readings.
///
/// Deliberately conservative. Odomind would rather say "not enough readings"
/// than produce a number an owner might act on. Sparse, stale or erratic history
/// lowers confidence or suppresses the estimate entirely.
public struct MileageEstimator: Sendable {
    /// Minimum number of days the readings must span.
    public static let minimumSpanDays = 14
    /// Beyond this, the latest reading is too old to project from.
    public static let stalenessLimitDays = 180
    /// A gap longer than this between consecutive readings is excluded from the
    /// rate calculation, because it usually means the owner stopped logging
    /// rather than stopped driving.
    public static let maximumUsefulGapDays = 400

    public init() {}

    /// Estimates from dated readings.
    ///
    /// - Parameters:
    ///   - ledger: the vehicle's readings, already on the cumulative scale.
    ///   - declaredTypicalDistancePerMonth: an explicit answer from the owner,
    ///     used when the readings alone are not enough.
    public func estimate(
        ledger: OdometerLedger,
        declaredTypicalDistancePerMonth: Distance? = nil,
        asOf now: Date,
        calendar: Calendar
    ) -> MileageEstimateResult {
        let unit = ledger.vehicle.displayUnit
        let readings = ledger.readings

        // A declared rate still needs a reading to project from, so no readings
        // means no estimate regardless of what the owner told us.
        guard let latest = readings.last else {
            return .unavailable(.noReadings)
        }

        let latestCumulative = ledger.cumulative(latest)
        let ageDays = DateSupport.dayCount(from: latest.recordedOn, to: now, in: calendar)

        if let declared = declaredTypicalDistancePerMonth, declared.amount > 0 {
            let perDay = Double(declared.converted(to: unit).amount) / 30.0
            return .available(
                MileageEstimate(
                    distancePerDay: perDay,
                    unit: unit,
                    confidence: ageDays > MileageEstimator.stalenessLimitDays ? .low : .medium,
                    basis: .ownerDeclaredTypicalDistance,
                    referenceOdometer: latestCumulative,
                    referenceDate: latest.recordedOn,
                    computedOn: now
                )
            )
        }

        guard readings.count >= 2 else {
            return .unavailable(.singleReading)
        }

        if ageDays > MileageEstimator.stalenessLimitDays {
            return .unavailable(
                .readingsTooStale(daysSinceLatest: ageDays, limit: MileageEstimator.stalenessLimitDays)
            )
        }

        // Use only consecutive pairs that represent plausible, non-negative
        // driving over a usable gap. A cluster of same-day readings or a
        // multi-year gap contributes nothing.
        var usableDistance = 0
        var usableDays = 0
        var usedPairs = 0
        for index in 1..<readings.count {
            let previous = readings[index - 1]
            let current = readings[index]
            let days = DateSupport.dayCount(from: previous.recordedOn, to: current.recordedOn, in: calendar)
            guard days >= 1, days <= MileageEstimator.maximumUsefulGapDays else { continue }
            let delta = (ledger.cumulative(current) - ledger.cumulative(previous)).converted(to: unit)
            guard delta.amount >= 0 else { continue }
            let perDay = delta.amount / days
            guard perDay <= OdometerLedger.implausibleDailyDistance(in: unit) else { continue }
            usableDistance += delta.amount
            usableDays += days
            usedPairs += 1
        }

        let totalSpan = DateSupport.dayCount(from: readings[0].recordedOn, to: latest.recordedOn, in: calendar)

        guard usedPairs > 0, usableDays >= MileageEstimator.minimumSpanDays else {
            if totalSpan < MileageEstimator.minimumSpanDays {
                return .unavailable(
                    .spanTooShort(days: max(totalSpan, 0), required: MileageEstimator.minimumSpanDays)
                )
            }
            return .unavailable(.noDistanceCovered)
        }

        guard usableDistance > 0 else {
            return .unavailable(.noDistanceCovered)
        }

        let perDay = Double(usableDistance) / Double(usableDays)
        let confidence = MileageEstimator.confidence(
            pairCount: usedPairs,
            spanDays: usableDays,
            latestAgeDays: ageDays
        )

        return .available(
            MileageEstimate(
                distancePerDay: perDay,
                unit: unit,
                confidence: confidence,
                basis: .recordedReadings(count: usedPairs + 1, spanDays: usableDays),
                referenceOdometer: latestCumulative,
                referenceDate: latest.recordedOn,
                computedOn: now
            )
        )
    }

    static func confidence(pairCount: Int, spanDays: Int, latestAgeDays: Int) -> EstimateConfidence {
        if pairCount >= 3, spanDays >= 90, latestAgeDays <= 45 {
            return .high
        }
        if pairCount >= 2, spanDays >= 45, latestAgeDays <= 90 {
            return .medium
        }
        return .low
    }
}
