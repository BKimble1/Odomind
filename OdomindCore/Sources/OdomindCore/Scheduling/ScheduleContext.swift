import Foundation

/// A completed instance of one task, projected onto the cumulative odometer
/// scale.
public struct ServiceCompletion: Hashable, Sendable {
    public var recordID: UUID
    public var definitionID: String
    public var performedOn: Date
    /// Cumulative odometer at the time of service, `nil` when the owner did not
    /// record one.
    public var cumulativeOdometer: Distance?

    public init(
        recordID: UUID,
        definitionID: String,
        performedOn: Date,
        cumulativeOdometer: Distance?
    ) {
        self.recordID = recordID
        self.definitionID = definitionID
        self.performedOn = performedOn
        self.cumulativeOdometer = cumulativeOdometer
    }
}

/// Everything the engine needs to evaluate one vehicle's plan.
///
/// The context is a value: nothing in the engine reads a clock, a database or a
/// user default, so the same context always produces the same evaluations.
public struct ScheduleContext: Sendable {
    public var vehicle: Vehicle
    public var ledger: OdometerLedger
    /// Completions grouped by task key, each list sorted oldest first.
    public var completions: [String: [ServiceCompletion]]
    public var estimate: MileageEstimate?
    public var estimateUnavailableReason: EstimateUnavailableReason?
    public var asOf: Date
    public var calendar: Calendar

    public init(
        vehicle: Vehicle,
        ledger: OdometerLedger,
        completions: [String: [ServiceCompletion]],
        estimate: MileageEstimate? = nil,
        estimateUnavailableReason: EstimateUnavailableReason? = nil,
        asOf: Date,
        calendar: Calendar
    ) {
        self.vehicle = vehicle
        self.ledger = ledger
        self.completions = completions
        self.estimate = estimate
        self.estimateUnavailableReason = estimateUnavailableReason
        self.asOf = asOf
        self.calendar = calendar
    }

    /// Builds a context from raw records, doing the odometer and estimate work
    /// once for the whole vehicle.
    public static func build(
        vehicle: Vehicle,
        readings: [OdometerReading],
        serviceRecords: [ServiceRecord],
        declaredTypicalDistancePerMonth: Distance? = nil,
        asOf: Date,
        calendar: Calendar,
        estimator: MileageEstimator = MileageEstimator()
    ) -> ScheduleContext {
        let ledger = OdometerLedger(vehicle: vehicle, readings: readings)

        var grouped: [String: [ServiceCompletion]] = [:]
        let relevant = serviceRecords.filter { $0.vehicleID == vehicle.id }
        for record in relevant {
            let cumulative = record.odometer.map {
                ledger.cumulative(rawValue: $0, on: record.performedOn)
            }
            for item in record.items {
                let completion = ServiceCompletion(
                    recordID: record.id,
                    definitionID: item.definitionID,
                    performedOn: record.performedOn,
                    cumulativeOdometer: cumulative
                )
                grouped[item.definitionID, default: []].append(completion)
            }
        }
        for key in grouped.keys {
            grouped[key]?.sort { lhs, rhs in
                if lhs.performedOn == rhs.performedOn {
                    return (lhs.cumulativeOdometer?.millimetres ?? 0) < (rhs.cumulativeOdometer?.millimetres ?? 0)
                }
                return lhs.performedOn < rhs.performedOn
            }
        }

        let estimateResult = estimator.estimate(
            ledger: ledger,
            declaredTypicalDistancePerMonth: declaredTypicalDistancePerMonth,
            asOf: asOf,
            calendar: calendar
        )

        return ScheduleContext(
            vehicle: vehicle,
            ledger: ledger,
            completions: grouped,
            estimate: estimateResult.estimate,
            estimateUnavailableReason: estimateResult.unavailableReason,
            asOf: asOf,
            calendar: calendar
        )
    }

    /// The newest completion for a task.
    ///
    /// Selected by service date, so logging a service you forgot about last year
    /// never displaces this year's oil change.
    public func latestCompletion(of definitionID: String) -> ServiceCompletion? {
        completions[definitionID]?.last
    }

    public func allCompletions(of definitionID: String) -> [ServiceCompletion] {
        completions[definitionID] ?? []
    }
}
