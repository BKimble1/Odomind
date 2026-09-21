import XCTest
@testable import OdomindCore

/// Pins the promise that a blank specification says where *that* value lives.
///
/// Build 1 sent everyone to the door placard. The placard carries tyre sizes
/// and cold pressures and nothing else — not an oil capacity, not a battery
/// group size, not a spark plug gap — so for most fields it was advice that
/// could not be followed. `docs/RELEASE-NOTES-BUILD-2.md` tells testers this
/// is fixed, which is a good reason for it to be checked rather than trusted.
final class SpecificationHintTests: XCTestCase {

    func testEveryKindSaysWhereToFindIt() {
        for kind in SpecificationKind.allCases {
            let hint = kind.sourceHint
            XCTAssertFalse(hint.isEmpty, "\(kind) has no source hint")
            XCTAssertGreaterThan(
                hint.count, 20,
                "\(kind)'s hint is too short to be telling anyone anything: \(hint)"
            )
        }
    }

    /// What the driver's door placard actually carries: the original tyre
    /// sizes and the cold pressures to run them at. Not the same set as
    /// `isVehiclePlacardOnly`, which is narrower — that one marks the values
    /// Odomind must never infer from a tyre sidewall, and a tyre *size* can
    /// legitimately be read off either.
    private static let onThePlacard: Set<SpecificationKind> = [
        .tireSizeFront, .tireSizeRear, .spareTireSize,
        .coldTirePressureFront, .coldTirePressureRear, .spareTirePressure,
    ]

    func testOnlyThePlacardFieldsSendYouToThePlacard() {
        for kind in SpecificationKind.allCases where !Self.onThePlacard.contains(kind) {
            XCTAssertFalse(
                kind.sourceHint.localizedCaseInsensitiveContains("placard"),
                "\(kind) sends people to the door placard, which does not carry it"
            )
        }
    }

    func testThePlacardFieldsDoNameThePlacard() {
        for kind in Self.onThePlacard {
            XCTAssertTrue(
                kind.sourceHint.localizedCaseInsensitiveContains("placard"),
                "\(kind) is on the placard but its hint does not say so"
            )
        }
    }

    func testTheTyrePressureHintWarnsOffTheSidewall() {
        // The specific wrong answer this field attracts: the sidewall number
        // is the tyre's maximum, not the pressure to run.
        for kind: SpecificationKind in [.coldTirePressureFront, .coldTirePressureRear, .spareTirePressure] {
            XCTAssertTrue(
                kind.sourceHint.localizedCaseInsensitiveContains("sidewall"),
                "\(kind) should say the sidewall number is not the answer"
            )
        }
    }

    func testTheBatteryHintNamesTheBatteryLabel() {
        let hint = SpecificationKind.batteryGroupSize.sourceHint
        XCTAssertTrue(
            hint.localizedCaseInsensitiveContains("battery"),
            "the battery group size should be read off the battery: \(hint)"
        )
    }
}
