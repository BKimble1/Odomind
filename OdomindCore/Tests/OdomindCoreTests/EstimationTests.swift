import XCTest
@testable import OdomindCore

final class MileageEstimatorTests: XCTestCase {
    let calendar = Calendar.utc
    let today = makeDate(2026, 6, 15)
    let estimator = MileageEstimator()

    private func ledger(_ readings: [OdometerReading], vehicle: Vehicle = Fixture.vehicle()) -> OdometerLedger {
        OdometerLedger(vehicle: vehicle, readings: readings)
    }

    func testNoReadingsProducesNoEstimate() {
        let result = estimator.estimate(ledger: ledger([]), asOf: today, calendar: calendar)
        XCTAssertEqual(result.unavailableReason, .noReadings)
        XCTAssertNil(result.estimate)
    }

    func testSingleReadingProducesNoEstimate() {
        let result = estimator.estimate(
            ledger: ledger([Fixture.reading(50_000, on: makeDate(2026, 6, 1))]),
            asOf: today,
            calendar: calendar
        )
        XCTAssertEqual(result.unavailableReason, .singleReading)
    }

    func testTooShortASpanProducesNoEstimate() {
        let result = estimator.estimate(
            ledger: ledger([
                Fixture.reading(50_000, on: makeDate(2026, 6, 10)),
                Fixture.reading(50_300, on: makeDate(2026, 6, 14))
            ]),
            asOf: today,
            calendar: calendar
        )
        guard case .spanTooShort(let days, let required)? = result.unavailableReason else {
            return XCTFail("expected spanTooShort, got \(String(describing: result.unavailableReason))")
        }
        XCTAssertEqual(days, 4)
        XCTAssertEqual(required, MileageEstimator.minimumSpanDays)
    }

    func testStaleReadingsSuppressTheEstimate() {
        let result = estimator.estimate(
            ledger: ledger([
                Fixture.reading(40_000, on: makeDate(2024, 1, 1)),
                Fixture.reading(45_000, on: makeDate(2024, 6, 1))
            ]),
            asOf: today,
            calendar: calendar
        )
        guard case .readingsTooStale(let age, let limit)? = result.unavailableReason else {
            return XCTFail("expected readingsTooStale")
        }
        XCTAssertGreaterThan(age, limit)
    }

    func testNoDistanceCoveredProducesNoEstimate() {
        let result = estimator.estimate(
            ledger: ledger([
                Fixture.reading(50_000, on: makeDate(2026, 3, 1)),
                Fixture.reading(50_000, on: makeDate(2026, 6, 1))
            ]),
            asOf: today,
            calendar: calendar
        )
        XCTAssertEqual(result.unavailableReason, .noDistanceCovered)
    }

    func testFourEvenReadingsGiveAHighConfidenceEstimate() {
        let result = estimator.estimate(
            ledger: ledger([
                Fixture.reading(50_000, on: makeDate(2026, 1, 1)),
                Fixture.reading(51_500, on: makeDate(2026, 2, 20)),
                Fixture.reading(53_000, on: makeDate(2026, 4, 10)),
                Fixture.reading(54_500, on: makeDate(2026, 5, 30))
            ]),
            asOf: today,
            calendar: calendar
        )
        guard let estimate = result.estimate else { return XCTFail("expected an estimate") }
        XCTAssertEqual(estimate.confidence, .high)
        XCTAssertEqual(estimate.distancePerDay, 30.0, accuracy: 1.0)
        XCTAssertEqual(estimate.referenceOdometer, Distance(54_500, .miles))
    }

    func testAnImplausiblePairIsExcludedFromTheRate() {
        // The middle reading is an obvious typo. It must not drag the rate up.
        let result = estimator.estimate(
            ledger: ledger([
                Fixture.reading(50_000, on: makeDate(2026, 1, 1)),
                Fixture.reading(500_500, on: makeDate(2026, 1, 2)),
                Fixture.reading(52_000, on: makeDate(2026, 5, 1))
            ]),
            asOf: today,
            calendar: calendar
        )
        // Both pairs are rejected (one implausible, one negative), so the
        // estimator declines rather than producing a nonsense number.
        XCTAssertNil(result.estimate)
    }

    func testOwnerDeclaredDistanceIsUsedWhenReadingsAreThin() {
        let result = estimator.estimate(
            ledger: ledger([Fixture.reading(50_000, on: makeDate(2026, 6, 1))]),
            declaredTypicalDistancePerMonth: Distance(900, .miles),
            asOf: today,
            calendar: calendar
        )
        guard let estimate = result.estimate else { return XCTFail("expected an estimate") }
        XCTAssertEqual(estimate.basis, .ownerDeclaredTypicalDistance)
        XCTAssertEqual(estimate.distancePerDay, 30.0, accuracy: 0.01)
        XCTAssertEqual(estimate.confidence, .medium)
    }

    func testProjectionOfADueOdometer() {
        let estimate = MileageEstimate(
            distancePerDay: 30,
            unit: .miles,
            confidence: .high,
            basis: .recordedReadings(count: 4, spanDays: 150),
            referenceOdometer: Distance(54_500, .miles),
            referenceDate: makeDate(2026, 5, 30),
            computedOn: today
        )
        let projected = estimate.projectedDate(reaching: Distance(55_400, .miles), calendar: calendar)
        XCTAssertNotNil(projected)
        XCTAssertEqual(DateSupport.dayCount(from: makeDate(2026, 5, 30), to: projected!, in: calendar), 30)
    }

    func testAStationaryVehicleProducesNoProjection() {
        let estimate = MileageEstimate(
            distancePerDay: 0,
            unit: .miles,
            confidence: .low,
            basis: .recordedReadings(count: 2, spanDays: 60),
            referenceOdometer: Distance(54_500, .miles),
            referenceDate: makeDate(2026, 5, 30),
            computedOn: today
        )
        XCTAssertNil(estimate.projectedDate(reaching: Distance(60_000, .miles), calendar: calendar))
    }
}

final class EstimateAndDueStateTests: XCTestCase {
    let calendar = Calendar.utc
    let today = makeDate(2026, 6, 15)

    /// Readings that produce a steady, high-confidence 30 miles a day.
    private var steadyReadings: [OdometerReading] {
        [
            Fixture.reading(50_000, on: makeDate(2026, 1, 1)),
            Fixture.reading(51_500, on: makeDate(2026, 2, 20)),
            Fixture.reading(53_000, on: makeDate(2026, 4, 10)),
            Fixture.reading(54_500, on: makeDate(2026, 5, 30))
        ]
    }

    func testAnEstimateCanWarnEarlyButNeverMarksSomethingOverdue() {
        // Serviced at 49,900, so due at 54,900. The last reading the owner
        // actually took was 54,500 on 30 May, which has not reached it. The
        // projection says the crossing happened around 12 June — in the past —
        // yet the task must still not be reported as overdue.
        let item = Fixture.planItem(rule: .distance(interval: Distance(5_000, .miles)))
        let context = Fixture.context(
            readings: steadyReadings,
            services: [Fixture.service(on: makeDate(2025, 12, 20), odometer: 49_900)],
            asOf: today
        )
        let result = ScheduleEngine.evaluate(item, in: context)

        XCTAssertEqual(result.nextDueOdometer, Distance(54_900, .miles))
        XCTAssertNotEqual(result.state, .overdue, "a projection must never produce an overdue claim")
        XCTAssertEqual(result.state, .dueSoon)
        XCTAssertEqual(result.distanceRemaining, Distance(400, .miles))
        guard let projected = result.estimatedDueDate else { return XCTFail("expected a projected date") }
        XCTAssertLessThan(projected, today, "the projected crossing is already behind us")
        XCTAssertEqual(result.estimateConfidence, .high)
        XCTAssertTrue(result.hasReason { if case .estimatedCrossing = $0 { return true }; return false })
        XCTAssertNil(result.nextDueDate, "an estimate is not a confirmed deadline")
    }

    func testRecordedOdometerAloneDecidesOverdue() {
        let item = Fixture.planItem(rule: .distance(interval: Distance(5_000, .miles)))
        var readings = steadyReadings
        readings.append(Fixture.reading(55_200, on: makeDate(2026, 6, 14)))
        let context = Fixture.context(
            readings: readings,
            services: [Fixture.service(on: makeDate(2025, 12, 20), odometer: 50_000)],
            asOf: today
        )
        let result = ScheduleEngine.evaluate(item, in: context)
        XCTAssertEqual(result.state, .overdue)
        XCTAssertTrue(result.hasReason { $0 == .overdueByDistance(Distance(200, .miles)) })
    }

    func testNoEstimateMeansNoProjectedDateAndAnExplanation() {
        let item = Fixture.planItem(rule: .distance(interval: Distance(5_000, .miles)))
        let context = Fixture.context(
            readings: [Fixture.reading(54_500, on: makeDate(2026, 5, 30))],
            services: [Fixture.service(on: makeDate(2025, 12, 20), odometer: 50_000)],
            asOf: today
        )
        let result = ScheduleEngine.evaluate(item, in: context)
        XCTAssertNil(result.estimatedDueDate)
        XCTAssertNil(result.estimateConfidence)
        XCTAssertTrue(result.hasReason { if case .estimateUnavailable = $0 { return true }; return false })
    }

    func testEstimateRecalculatesWhenAReadingIsAdded() {
        let item = Fixture.planItem(rule: .distance(interval: Distance(10_000, .miles)))
        let services = [Fixture.service(on: makeDate(2025, 12, 20), odometer: 50_000)]

        let before = ScheduleEngine.evaluate(
            item,
            in: Fixture.context(readings: steadyReadings, services: services, asOf: today)
        )

        // A much larger recent jump raises the rate, so the projected date moves
        // closer.
        var faster = steadyReadings
        faster.append(Fixture.reading(58_000, on: makeDate(2026, 6, 14)))
        let after = ScheduleEngine.evaluate(
            item,
            in: Fixture.context(readings: faster, services: services, asOf: today)
        )

        XCTAssertNotNil(before.estimatedDueDate)
        XCTAssertNotNil(after.estimatedDueDate)
        XCTAssertLessThan(after.estimatedDueDate!, before.estimatedDueDate!)
    }
}
