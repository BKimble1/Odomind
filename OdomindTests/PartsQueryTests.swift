import XCTest
@testable import Odomind
import OdomindCore

/// What actually goes into a retailer's search box, and what must never.
final class PartsQueryTests: XCTestCase {

    private func jeep() -> Vehicle {
        var vehicle = Vehicle(
            nickname: "Blue one",
            identity: VehicleIdentity(
                modelYear: 2010,
                make: "Jeep",
                model: "Wrangler",
                trim: "Unlimited Sport",
                vin: "1J4BA3H14AL139999",
                identityProvenance: .referenceSourced
            )
        )
        vehicle.displayUnit = .miles
        return vehicle
    }

    func testTheQueryCarriesYearMakeAndModel() {
        let query = PartsQueryBuilder.query(for: jeep(), part: "oil filter")
        for expected in ["2010", "Jeep", "Wrangler", "oil filter"] {
            XCTAssertTrue(query.contains(expected), "\(expected) missing from \(query)")
        }
    }

    func testARecordedSpecificationSharpensTheQuery() {
        // The finding this fixes: the owner had recorded "Group 34" and the
        // search still went out as "2010 Jeep Wrangler battery".
        let query = PartsQueryBuilder.query(for: jeep(), part: "battery", specification: "Group 34")
        XCTAssertTrue(query.contains("Group 34"), "the recorded specification should be searched with: \(query)")
        XCTAssertTrue(query.contains("battery"))
    }

    func testTheVINNeverReachesARetailer() {
        let query = PartsQueryBuilder.query(for: jeep(), part: "oil filter", specification: "5W-20")
        XCTAssertFalse(query.contains("1J4BA3H14AL139999"), "a VIN identifies one car and is nobody's business")
        XCTAssertFalse(query.lowercased().contains("1j4ba3h"))
    }

    func testTheOwnersNicknameNeverReachesARetailer() {
        let query = PartsQueryBuilder.query(for: jeep(), part: "oil filter")
        XCTAssertFalse(query.contains("Blue one"), "what the owner calls their car is not search terms")
    }

    func testTheQueryIsSafeInsideAURL() {
        // A part name containing & or ? must not add a parameter to somebody
        // else's URL.
        let retailer = Retailer.all.first { $0.acceptsPrefilledSearch }
        let built = retailer?.url(for: "filter & bolt ?x=1#frag")
        guard let built else { return XCTFail("no retailer accepts a prefilled search") }
        let tail = built.absoluteString.replacingOccurrences(of: "https://", with: "")
        XCTAssertFalse(tail.contains("&x="), "an injected parameter survived: \(built)")
        XCTAssertFalse(built.absoluteString.contains("#frag"), "an injected fragment survived: \(built)")
    }

    func testTheFitmentCaveatDoesNotPromiseFit() {
        let caveat = PartsQueryBuilder.fitmentCaveat
        XCTAssertFalse(caveat.isEmpty)
        XCTAssertTrue(
            caveat.lowercased().contains("not a guarantee")
                || caveat.lowercased().contains("starting point"),
            "the caveat has to say a model match is not a fitment guarantee: \(caveat)"
        )
    }

    func testShoppingCapabilityStaysBelowLicensedOffers() {
        // Pinned deliberately. Raising this is a claim about data Odomind
        // does not have, and the screens read it to decide what they may say.
        XCTAssertLessThan(
            ShoppingCapability.current, .licensedOffers,
            "no licensed parts catalogue is in place — see docs/PROVIDERS.md"
        )
    }
}
