import XCTest
@testable import Odomind
import OdomindCore

/// Changing which vehicle is selected must not leave pieces of the last one
/// attached to it.
///
/// Build 2's `select` explicitly copied the previous VIN and trim onto the new
/// identity and left `configuration` untouched, so a VIN-decoded Jeep followed
/// by a Camry produced a Camry carrying the Jeep's VIN and its 3.8 litre
/// four-wheel drive. The draft is the same shape the flow uses, so these
/// exercise the real rule rather than a copy of it.
@MainActor
final class VehicleIdentityTests: XCTestCase {

    /// The rule under test, as the flow applies it.
    private func select(_ result: VehicleSearchResult, into draft: inout VehicleDraft) {
        let sameVehicle = draft.identity.make.caseInsensitiveCompare(result.make) == .orderedSame
            && draft.identity.model.caseInsensitiveCompare(result.model) == .orderedSame
        guard !sameVehicle else {
            draft.identity.modelYear = result.modelYear ?? draft.identity.modelYear
            return
        }
        draft.identity = result.identity
        draft.configuration = VehicleConfiguration()
        draft.decodeResult = nil
        draft.identity.trim = nil
    }

    private func decodedJeep() -> VehicleDraft {
        var draft = VehicleDraft()
        draft.identity = VehicleIdentity(
            modelYear: 2010,
            make: "Jeep",
            model: "Wrangler",
            trim: "Unlimited X",
            vin: "1J4BA3H14AL139999",
            identityProvenance: .referenceSourced
        )
        draft.configuration = VehicleConfiguration(
            powertrain: .gasoline,
            engineDisplacementLiters: 3.8,
            transmission: .automatic,
            drivetrain: .fourWheelDrivePartTime,
            camshaftDrive: .timingChain,
            market: .unitedStates
        )
        return draft
    }

    func testChoosingADifferentVehicleDropsTheOldVIN() {
        var draft = decodedJeep()
        XCTAssertNotNil(draft.identity.vin)

        select(VehicleSearchResult(modelYear: 2015, make: "Toyota", model: "Camry", origin: .referenceSourced), into: &draft)

        XCTAssertNil(draft.identity.vin, "a VIN identifies one specific vehicle and cannot follow another")
        XCTAssertEqual(draft.identity.make, "Toyota")
        XCTAssertEqual(draft.identity.model, "Camry")
    }

    func testChoosingADifferentVehicleDropsTheOldTrim() {
        var draft = decodedJeep()
        select(VehicleSearchResult(modelYear: 2015, make: "Toyota", model: "Camry", origin: .referenceSourced), into: &draft)
        XCTAssertNil(draft.identity.trim, "\"Unlimited X\" is a Wrangler trim and means nothing on a Camry")
    }

    func testChoosingADifferentVehicleDropsTheDecodedConfiguration() {
        var draft = decodedJeep()
        select(VehicleSearchResult(modelYear: 2015, make: "Toyota", model: "Camry", origin: .referenceSourced), into: &draft)

        XCTAssertNil(draft.configuration.engineDisplacementLiters, "the Jeep's 3.8 must not describe the Camry")
        XCTAssertEqual(draft.configuration.drivetrain, .unknown, "nor its four-wheel drive")
        XCTAssertEqual(draft.configuration.powertrain, .unknown)
        XCTAssertEqual(draft.configuration.transmission, .unknown)
        XCTAssertNil(draft.decodeResult, "nor the decode it all came from")
    }

    func testRetappingTheSameVehicleKeepsWhatWasConfirmed() {
        var draft = decodedJeep()
        select(VehicleSearchResult(modelYear: 2010, make: "Jeep", model: "Wrangler", origin: .referenceSourced), into: &draft)

        XCTAssertEqual(draft.identity.vin, "1J4BA3H14AL139999", "re-selecting the same vehicle is not a change")
        XCTAssertEqual(draft.configuration.engineDisplacementLiters, 3.8)
    }

    func testAYearlessResultKeepsAYearAlreadyChosenForTheSameVehicle() {
        var draft = decodedJeep()
        select(VehicleSearchResult(modelYear: nil, make: "Jeep", model: "Wrangler", origin: .referenceSourced), into: &draft)
        XCTAssertEqual(draft.identity.modelYear, 2010, "a yearless row must not clear a year already settled")
    }

    func testADifferentModelFromTheSameMakeIsStillADifferentVehicle() {
        var draft = decodedJeep()
        select(VehicleSearchResult(modelYear: 2010, make: "Jeep", model: "Cherokee", origin: .referenceSourced), into: &draft)

        XCTAssertNil(draft.identity.vin, "a Wrangler's VIN is not a Cherokee's")
        XCTAssertNil(draft.configuration.engineDisplacementLiters)
        XCTAssertEqual(draft.configuration.drivetrain, .unknown)
    }
}
