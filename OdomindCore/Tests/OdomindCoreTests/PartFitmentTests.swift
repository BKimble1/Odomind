import XCTest
@testable import OdomindCore

/// The rules that stop Odomind telling somebody a part fits when it does not.
///
/// Each of these is a way a parts feature goes wrong in the wild: a qualifier
/// quietly dropped, a superseded number still sold, a retailer's SKU shown as
/// the part number, or "cheapest nearby" claimed from a single price.
final class PartFitmentTests: XCTestCase {

    private func filter(
        applicability: PartApplicability = .confirmed,
        qualifiers: [String] = [],
        supersededBy: String? = nil
    ) -> PartReference {
        PartReference(
            id: "test:oil-filter",
            brand: "Mopar",
            manufacturerPartNumber: "MO-899",
            category: "engineOilFilter",
            qualifiers: qualifiers,
            applicability: applicability,
            supersededBy: supersededBy,
            sourceName: "Test catalogue",
            retrievedOn: Date(timeIntervalSince1970: 1_790_000_000)
        )
    }

    // MARK: - Confirmed means confirmed

    func testAConfirmedPartFits() {
        XCTAssertTrue(filter().fitsConfirmed)
        XCTAssertEqual(filter().fitSummary, "Fits your vehicle")
    }

    func testAnUnansweredQuestionIsNotAConfirmedFit() {
        let part = filter(applicability: .conditional(missing: ["the engine is the 3.8 litre"]))
        XCTAssertFalse(part.fitsConfirmed, "a conditional result is not a confirmed fit")
        XCTAssertTrue(part.fitSummary.contains("does not know"))
    }

    func testAWrongEngineIsReportedAsNotFitting() {
        let part = filter(applicability: .notApplicable(reason: "this is for the 2.8 litre diesel"))
        XCTAssertFalse(part.fitsConfirmed)
        XCTAssertTrue(part.fitSummary.hasPrefix("Does not fit"))
    }

    func testASupersededNumberIsNeverAConfirmedFit() {
        // The old record may still be technically applicable; it is still not
        // the number to buy.
        let part = filter(applicability: .confirmed, supersededBy: "MO-899A")
        XCTAssertFalse(part.fitsConfirmed)
        XCTAssertTrue(part.fitSummary.contains("MO-899A"))
    }

    func testAQualifierIsShownRatherThanSwallowed() {
        let part = filter(qualifiers: ["with 3.8L engine"])
        XCTAssertTrue(part.fitsConfirmed)
        XCTAssertTrue(
            part.fitSummary.contains("with 3.8L engine"),
            "a condition the catalogue attached must survive to the screen"
        )
    }

    func testEveryApplicabilityStateSaysSomething() {
        let states: [PartApplicability] = [
            .confirmed,
            .conditional(missing: ["something"]),
            .notApplicable(reason: "something"),
        ]
        for state in states {
            XCTAssertFalse(filter(applicability: state).fitSummary.isEmpty)
        }
    }

    // MARK: - A part number is not a SKU

    func testAnOfferKeepsTheRetailerSKUSeparateFromThePartNumber() {
        let offer = PartOffer(
            id: "test:offer",
            manufacturerPartNumber: "MO-899",
            retailerName: "Example Parts",
            retailerSKU: "EP-11223",
            retrievedOn: Date(timeIntervalSince1970: 1_790_000_000)
        )
        XCTAssertEqual(offer.manufacturerPartNumber, "MO-899")
        XCTAssertNotEqual(offer.retailerSKU, offer.manufacturerPartNumber)
    }

    // MARK: - Comparing prices

    private func offer(_ name: String, _ amount: Decimal?) -> PartOffer {
        PartOffer(
            id: "test:\(name)",
            manufacturerPartNumber: "MO-899",
            retailerName: name,
            price: amount.map { Money(amount: $0, currencyCode: "USD") },
            retrievedOn: Date(timeIntervalSince1970: 1_790_000_000)
        )
    }

    func testOnePriceIsNotAComparison() {
        let result = PartResult(reference: filter(), offers: [offer("A", 12.99)])
        XCTAssertNil(result.comparableBest, "a single offer cannot be the cheapest of anything")
    }

    func testNoPricesIsNotAComparison() {
        let result = PartResult(reference: filter(), offers: [offer("A", nil), offer("B", nil)])
        XCTAssertNil(result.comparableBest)
    }

    func testTwoRealPricesCanBeCompared() {
        let result = PartResult(
            reference: filter(),
            offers: [offer("A", 12.99), offer("B", 9.49)]
        )
        XCTAssertEqual(result.comparableBest?.retailerName, "B")
    }

    func testAnOfferWithoutAPriceIsNotTreatedAsFree() {
        let result = PartResult(
            reference: filter(),
            offers: [offer("A", 12.99), offer("B", nil), offer("C", 15.00)]
        )
        XCTAssertEqual(result.comparableBest?.retailerName, "A", "a missing price is missing, not zero")
    }
}
