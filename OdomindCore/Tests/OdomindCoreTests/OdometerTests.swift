import XCTest
@testable import OdomindCore

final class OdometerLedgerTests: XCTestCase {
    let calendar = Calendar.utc
    let today = makeDate(2026, 6, 15)

    func testCumulativeEqualsRawWithoutReplacements() {
        let vehicle = Fixture.vehicle()
        let ledger = OdometerLedger(
            vehicle: vehicle,
            readings: [Fixture.reading(52_000, on: makeDate(2026, 6, 1))]
        )
        XCTAssertEqual(ledger.latestCumulative, Distance(52_000, .miles))
    }

    func testReplacementKeepsHistoryOnOneScale() {
        // Cluster replaced at 130,000 with a unit showing 0. A reading of 400
        // afterwards is really 130,400 on the vehicle.
        let replacement = OdometerReplacement(
            occurredOn: makeDate(2026, 3, 1),
            previousUnitFinalReading: Distance(130_000, .miles),
            replacementUnitStartReading: Distance(0, .miles)
        )
        let vehicle = Fixture.vehicle(replacements: [replacement])
        let ledger = OdometerLedger(
            vehicle: vehicle,
            readings: [
                Fixture.reading(129_000, on: makeDate(2026, 1, 1)),
                Fixture.reading(400, on: makeDate(2026, 5, 1))
            ]
        )
        XCTAssertEqual(ledger.latestCumulative, Distance(130_400, .miles))
        XCTAssertEqual(ledger.rawValue(cumulative: Distance(130_400, .miles), on: makeDate(2026, 5, 1)), Distance(400, .miles))
    }

    func testSchedulingUsesTheCumulativeScaleAcrossAReplacement() {
        let replacement = OdometerReplacement(
            occurredOn: makeDate(2026, 3, 1),
            previousUnitFinalReading: Distance(130_000, .miles),
            replacementUnitStartReading: Distance(0, .miles)
        )
        let vehicle = Fixture.vehicle(replacements: [replacement])
        let item = Fixture.planItem(rule: .distance(interval: Distance(5_000, .miles)))
        let context = Fixture.context(
            vehicle: vehicle,
            readings: [Fixture.reading(1_200, on: makeDate(2026, 6, 1))],
            services: [Fixture.service(on: makeDate(2026, 1, 15), odometer: 128_000)],
            asOf: today
        )
        let result = ScheduleEngine.evaluate(item, in: context)
        // Serviced at 128,000, so due at 133,000 cumulative; now at 131,200.
        XCTAssertEqual(result.nextDueOdometer, Distance(133_000, .miles))
        XCTAssertEqual(result.distanceRemaining, Distance(1_800, .miles))
    }

    func testDecreaseIsFlaggedButNotTreatedAsAReplacement() {
        let ledger = OdometerLedger(
            vehicle: Fixture.vehicle(),
            readings: [Fixture.reading(52_000, on: makeDate(2026, 5, 1))]
        )
        let issues = ledger.issues(
            forProposed: Distance(5_200, .miles),
            on: makeDate(2026, 6, 1),
            now: today,
            calendar: calendar
        )
        XCTAssertTrue(issues.contains { if case .decreasedFromEarlier = $0 { return true }; return false })
        XCTAssertFalse(issues.contains { $0.isBlocking }, "a decrease is a question for the owner, not a hard error")
    }

    func testFutureDatedAndNegativeReadingsAreBlocking() {
        let ledger = OdometerLedger(vehicle: Fixture.vehicle(), readings: [])
        let future = ledger.issues(
            forProposed: Distance(1_000, .miles),
            on: makeDate(2026, 8, 1),
            now: today,
            calendar: calendar
        )
        XCTAssertTrue(future.contains { if case .futureDated = $0 { return true }; return false })
        XCTAssertTrue(future.contains { $0.isBlocking })

        let negative = ledger.issues(
            forProposed: Distance(-5, .miles),
            on: today,
            now: today,
            calendar: calendar
        )
        XCTAssertTrue(negative.contains(.negativeValue))
    }

    func testImplausibleJumpIsFlagged() {
        let ledger = OdometerLedger(
            vehicle: Fixture.vehicle(),
            readings: [Fixture.reading(52_000, on: makeDate(2026, 6, 1))]
        )
        // An extra digit: 520,000 instead of 52,000, two days later.
        let issues = ledger.issues(
            forProposed: Distance(520_000, .miles),
            on: makeDate(2026, 6, 3),
            now: today,
            calendar: calendar
        )
        XCTAssertTrue(issues.contains { if case .implausibleIncrease = $0 { return true }; return false })
    }

    func testDuplicateSameDayReadingIsFlagged() {
        let ledger = OdometerLedger(
            vehicle: Fixture.vehicle(),
            readings: [Fixture.reading(52_000, on: makeDate(2026, 6, 10, hour: 9))]
        )
        let issues = ledger.issues(
            forProposed: Distance(52_000, .miles),
            on: makeDate(2026, 6, 10, hour: 18),
            now: today,
            calendar: calendar
        )
        XCTAssertTrue(issues.contains { if case .duplicateOfExisting = $0 { return true }; return false })
    }

    func testReadingsFromOtherVehiclesAreIgnored() {
        let otherVehicleID = UUID()
        let ledger = OdometerLedger(
            vehicle: Fixture.vehicle(),
            readings: [
                Fixture.reading(52_000, on: makeDate(2026, 6, 1)),
                Fixture.reading(999_999, on: makeDate(2026, 6, 10), vehicleID: otherVehicleID)
            ]
        )
        XCTAssertEqual(ledger.readings.count, 1)
        XCTAssertEqual(ledger.latestCumulative, Distance(52_000, .miles))
    }
}

final class ServiceRecordValidationTests: XCTestCase {
    let calendar = Calendar.utc
    let today = makeDate(2026, 6, 15)

    private var ledger: OdometerLedger {
        OdometerLedger(
            vehicle: Fixture.vehicle(),
            readings: [Fixture.reading(52_000, on: makeDate(2026, 6, 1))]
        )
    }

    func testFutureDatedServiceIsBlocked() {
        let record = Fixture.service(on: makeDate(2026, 7, 1), odometer: 53_000)
        let issues = ServiceRecordValidator.issues(for: record, ledger: ledger, now: today, calendar: calendar)
        XCTAssertTrue(issues.contains { if case .futureDated = $0 { return true }; return false })
        XCTAssertTrue(issues.contains { $0.isBlocking })
    }

    func testEmptyVisitIsBlocked() {
        let record = ServiceRecord(vehicleID: Fixture.vehicleID, performedOn: today, items: [])
        let issues = ServiceRecordValidator.issues(for: record, ledger: ledger, now: today, calendar: calendar)
        XCTAssertTrue(issues.contains(.noItems))
    }

    func testDuplicateTaskInOneVisitIsBlocked() {
        let record = Fixture.service(
            on: today,
            odometer: 52_500,
            definitionIDs: ["engine-oil-and-filter", "engine-oil-and-filter"]
        )
        let issues = ServiceRecordValidator.issues(for: record, ledger: ledger, now: today, calendar: calendar)
        XCTAssertTrue(issues.contains { if case .duplicateDefinition = $0 { return true }; return false })
    }

    func testMixedCurrenciesInOneVisitAreBlocked() {
        var record = Fixture.service(
            on: today,
            odometer: 52_500,
            definitionIDs: ["engine-oil-and-filter", "tire-rotation"],
            totalCost: Money(amount: 100, currencyCode: "USD")
        )
        record.items[0].itemCost = Money(amount: 60, currencyCode: "CAD")
        let issues = ServiceRecordValidator.issues(for: record, ledger: ledger, now: today, calendar: calendar)
        XCTAssertTrue(issues.contains(.mixedCurrencies))
    }

    func testItemisedCostsAboveTheTotalAreAWarning() {
        var record = Fixture.service(
            on: today,
            odometer: 52_500,
            definitionIDs: ["engine-oil-and-filter", "tire-rotation"],
            totalCost: Money(amount: 50, currencyCode: "USD")
        )
        record.items[0].itemCost = Money(amount: 40, currencyCode: "USD")
        record.items[1].itemCost = Money(amount: 30, currencyCode: "USD")
        let issues = ServiceRecordValidator.issues(for: record, ledger: ledger, now: today, calendar: calendar)
        XCTAssertTrue(issues.contains(.itemCostsExceedTotal))
        XCTAssertFalse(issues.contains { $0.isBlocking })
    }

    func testAMultiTaskVisitTotalIsCountedOnceNotPerTask() {
        let record = Fixture.service(
            on: today,
            odometer: 52_500,
            definitionIDs: ["engine-oil-and-filter", "tire-rotation", "cabin-air-filter"],
            totalCost: Money(amount: Decimal(string: "89.97")!, currencyCode: "USD")
        )
        let total = MoneyTotal.total(of: [record].compactMap(\.totalCost))
        guard case .single(let sum) = total else { return XCTFail("expected one currency") }
        XCTAssertEqual(sum.amount, Decimal(string: "89.97")!)
        XCTAssertEqual(record.items.count, 3, "three tasks, one charge")
    }
}
