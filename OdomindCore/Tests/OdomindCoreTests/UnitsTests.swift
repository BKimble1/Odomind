import XCTest
@testable import OdomindCore

final class DistanceTests: XCTestCase {

    func testComparisonUsesExactIntegerScale() {
        // 1 mile is exactly 1609.344 m, so both units land on whole millimetres
        // and comparison is exact rather than approximate.
        XCTAssertEqual(Distance(1, .miles).millimetres, 1_609_344)
        XCTAssertEqual(Distance(1, .kilometers).millimetres, 1_000_000)
        XCTAssertTrue(Distance(1, .miles) > Distance(1, .kilometers))
        XCTAssertTrue(Distance(100, .kilometers) > Distance(62, .miles))
        XCTAssertTrue(Distance(62, .miles) < Distance(100, .kilometers))
    }

    func testEqualityAndHashingAgree() {
        let a = Distance(5000, .miles)
        let b = Distance(5000, .miles)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.hashValue, b.hashValue)

        // Different units with different real lengths are not equal.
        XCTAssertNotEqual(Distance(1000, .miles), Distance(1609, .kilometers))
    }

    func testRepeatedConversionDoesNotDrift() {
        // Round-tripping a value must not slowly wander. The engine relies on
        // this when a kilometre vehicle uses a mile-denominated template.
        var value = Distance(120_000, .kilometers)
        for _ in 0..<50 {
            value = value.converted(to: .miles).converted(to: .kilometers)
        }
        XCTAssertLessThanOrEqual(abs(value.amount - 120_000), 2, "conversion drifted to \(value.amount)")
    }

    func testArithmeticKeepsLeftHandUnit() {
        let sum = Distance(100, .miles) + Distance(10, .kilometers)
        XCTAssertEqual(sum.unit, .miles)
        XCTAssertEqual(sum.amount, 106)

        let difference = Distance(100, .kilometers) - Distance(10, .miles)
        XCTAssertEqual(difference.unit, .kilometers)
        XCTAssertEqual(difference.amount, 84)
    }

    func testNegativeDeltaAndMagnitude() {
        let remaining = Distance(4_800, .miles) - Distance(5_000, .miles)
        XCTAssertEqual(remaining.amount, -200)
        XCTAssertTrue(remaining.isNegative)
        XCTAssertEqual(remaining.magnitude.amount, 200)
    }

    func testCodableRoundTrip() throws {
        let value = Distance(7_500, .kilometers)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(Distance.self, from: data)
        XCTAssertEqual(decoded, value)
        XCTAssertEqual(decoded.unit, .kilometers)
    }

    func testThousandsFormatting() {
        XCTAssertEqual(5_000.formattedWithSeparators, "5,000")
        XCTAssertEqual(120.formattedWithSeparators, "120")
        XCTAssertEqual(1_234_567.formattedWithSeparators, "1,234,567")
        XCTAssertEqual((-4_500).formattedWithSeparators, "-4,500")
        XCTAssertEqual(0.formattedWithSeparators, "0")
    }
}

final class CalendarIntervalTests: XCTestCase {

    func testMonthEndClamping() {
        // 31 August plus six months is 28 February, not 31 February or 3 March.
        let calendar = Calendar.utc
        let start = makeDate(2025, 8, 31, calendar: calendar)
        let due = CalendarInterval.months(6).advancing(start, in: calendar)
        XCTAssertNotNil(due)
        let components = calendar.dateComponents([.year, .month, .day], from: due!)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 2)
        XCTAssertEqual(components.day, 28)
    }

    func testLeapDayPlusOneYear() {
        let calendar = Calendar.utc
        let leapDay = makeDate(2024, 2, 29, calendar: calendar)
        let due = CalendarInterval.years(1).advancing(leapDay, in: calendar)
        let components = calendar.dateComponents([.year, .month, .day], from: due!)
        XCTAssertEqual(components.year, 2025)
        XCTAssertEqual(components.month, 2)
        XCTAssertEqual(components.day, 28)
    }

    func testLeapDayPlusFourYearsLandsOnLeapDay() {
        let calendar = Calendar.utc
        let leapDay = makeDate(2024, 2, 29, calendar: calendar)
        let due = CalendarInterval.years(4).advancing(leapDay, in: calendar)
        let components = calendar.dateComponents([.year, .month, .day], from: due!)
        XCTAssertEqual(components.month, 2)
        XCTAssertEqual(components.day, 29)
    }

    func testDayCountIgnoresTimeOfDay() {
        let calendar = Calendar.utc
        let lateToday = makeDate(2026, 3, 1, hour: 23, minute: 30, calendar: calendar)
        let earlyTomorrow = makeDate(2026, 3, 2, hour: 0, minute: 15, calendar: calendar)
        XCTAssertEqual(DateSupport.dayCount(from: lateToday, to: earlyTomorrow, in: calendar), 1)
    }

    func testDaylightSavingTransitionStillCountsWholeDays() {
        // US spring-forward 2026 is 8 March. A day either side of it is still
        // one day apart, even though it is only 23 hours long.
        let calendar = Calendar.fixed("America/New_York")
        let before = makeDate(2026, 3, 7, hour: 12, calendar: calendar)
        let after = makeDate(2026, 3, 8, hour: 12, calendar: calendar)
        XCTAssertEqual(DateSupport.dayCount(from: before, to: after, in: calendar), 1)
    }

    func testWeeksConvertToDays() {
        let calendar = Calendar.utc
        let start = makeDate(2026, 1, 1, calendar: calendar)
        let due = CalendarInterval.weeks(2).advancing(start, in: calendar)!
        XCTAssertEqual(DateSupport.dayCount(from: start, to: due, in: calendar), 14)
    }
}

final class MoneyTests: XCTestCase {

    func testDecimalAmountsAreExact() {
        let a = Money(amount: Decimal(string: "89.97")!, currencyCode: "usd")
        XCTAssertEqual(a.currencyCode, "USD")

        let total = MoneyTotal.total(of: [
            Money(amount: Decimal(string: "0.10")!, currencyCode: "USD"),
            Money(amount: Decimal(string: "0.20")!, currencyCode: "USD")
        ])
        guard case .single(let sum) = total else { return XCTFail("expected a single currency total") }
        XCTAssertEqual(sum.amount, Decimal(string: "0.30")!)
    }

    func testMixedCurrenciesAreNotCombined() {
        let total = MoneyTotal.total(of: [
            Money(amount: 50, currencyCode: "USD"),
            Money(amount: 40, currencyCode: "CAD"),
            Money(amount: 10, currencyCode: "USD")
        ])
        XCTAssertTrue(total.isMixedCurrency)
        XCTAssertEqual(total.components.count, 2)
        XCTAssertEqual(total.components.first?.currencyCode, "USD")
        XCTAssertEqual(total.components.first?.amount, 60)
        XCTAssertEqual(total.components.last?.currencyCode, "CAD")
        XCTAssertEqual(total.components.last?.amount, 40)
    }

    func testEmptyTotal() {
        XCTAssertEqual(MoneyTotal.total(of: [Money]()), .empty)
        XCTAssertTrue(MoneyTotal.empty.components.isEmpty)
    }

    func testPlainDecimalTextIsLocaleIndependent() {
        XCTAssertEqual(DecimalText.plain(Decimal(string: "89.97")!), "89.97")
        XCTAssertEqual(DecimalText.plain(Decimal(string: "1200")!), "1200")
        XCTAssertEqual(DecimalText.plain(Decimal(string: "0.005")!), "0.01")
    }
}
