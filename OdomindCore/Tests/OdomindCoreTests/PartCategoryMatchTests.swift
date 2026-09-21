import XCTest
@testable import OdomindCore

/// Reading a parts search for what it is about.
///
/// The Build 2 defect these guard: the Parts screen showed a fixed four
/// specifications — oil viscosity, oil capacity, tyre size and battery group
/// — whatever had been typed, so looking up a cabin filter put a tyre size in
/// front of the owner and left out the number that identifies the filter.
final class PartCategoryMatchTests: XCTestCase {

    func testAFilterLookupDoesNotBringTyresAndBatteries() {
        let kinds = PartCategoryMatch.specifications(for: "cabin air filter")
        XCTAssertEqual(kinds, [.cabinAirFilterPartNumber])
        XCTAssertFalse(kinds.contains(.tireSizeFront))
        XCTAssertFalse(kinds.contains(.batteryGroupSize))
    }

    func testTheMoreSpecificCategoryWins() {
        // "cabin air filter" contains "air filter", which contains nothing
        // else. Reading it as the engine's would be the wrong part.
        XCTAssertEqual(PartCategoryMatch.category(for: "cabin air filter"), .cabinAirFilter)
        XCTAssertEqual(PartCategoryMatch.category(for: "engine air filter"), .engineAirFilter)
        // "oil filter" contains "oil". A filter is not a litre of oil.
        XCTAssertEqual(PartCategoryMatch.category(for: "oil filter"), .oilFilter)
        XCTAssertEqual(PartCategoryMatch.category(for: "engine oil"), .engineOil)
    }

    func testAnOilChangeReachesItsOilAndItsFilter() {
        // The brief: "An oil-change job should connect directly to its oil and
        // filter categories."
        let kinds = PartCategoryMatch.specifications(for: "Engine oil and filter")
        XCTAssertTrue(kinds.contains(.engineOilFilterPartNumber), "got \(kinds)")
        XCTAssertTrue(kinds.contains(.engineOilViscosity), "got \(kinds)")
        XCTAssertTrue(kinds.contains(.engineOilCapacityWithFilter), "got \(kinds)")
    }

    func testOrdinaryCategoriesAreRecognised() {
        XCTAssertEqual(PartCategoryMatch.category(for: "front brake pads"), .brakes)
        XCTAssertEqual(PartCategoryMatch.category(for: "battery"), .battery)
        XCTAssertEqual(PartCategoryMatch.category(for: "tire rotation"), .tires)
        XCTAssertEqual(PartCategoryMatch.category(for: "spark plugs"), .sparkPlugs)
        XCTAssertEqual(PartCategoryMatch.category(for: "wiper blades"), .wiperBlades)
        XCTAssertEqual(PartCategoryMatch.category(for: "transfer case service"), .transferCaseFluid)
        XCTAssertEqual(PartCategoryMatch.category(for: "coolant flush"), .coolant)
    }

    func testAWordInsideAnotherWordIsNotAMatch() {
        // "oil" inside "coil" would make an ignition coil an oil change.
        XCTAssertNotEqual(PartCategoryMatch.category(for: "ignition coil pack"), .engineOil)
    }

    func testAnUnrecognisedQueryGetsTheGeneralSetRatherThanAGuess() {
        XCTAssertEqual(
            PartCategoryMatch.specifications(for: "zzzq widget"),
            PartCategoryMatch.generalSpecifications
        )
        XCTAssertEqual(
            PartCategoryMatch.specifications(for: ""),
            PartCategoryMatch.generalSpecifications
        )
    }

    func testTheJobsCategoryIsUsedOnlyWhenTheTextSaysNothing() {
        // Typed text beats the category the screen was opened with, because
        // the owner typed it more recently.
        XCTAssertEqual(
            PartCategoryMatch.category(for: "battery", categoryHint: "Engine"),
            .battery
        )
        XCTAssertEqual(
            PartCategoryMatch.category(for: "", categoryHint: "Brakes"),
            .brakes
        )
    }
}
