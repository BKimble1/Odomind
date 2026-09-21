import XCTest
@testable import OdomindCore

/// Artwork resolution is a presentation decision, but it is the one place
/// where a wrong answer is visible on every screen — so the rules that pick a
/// drawing are tested like any other rule.
final class ArtworkTests: XCTestCase {

    // MARK: - Body style

    func testAnOffRoadNameBeatsTheBroadSUVBodyClass() {
        // vPIC reports a Wrangler and a small crossover with the same
        // BodyClass string. The model name is the only thing that separates
        // them, which is why it is checked first.
        let wrangler = VehicleIdentity(
            modelYear: 2010,
            make: "Jeep",
            model: "Wrangler",
            bodyClass: "Sport Utility Vehicle (SUV)/Multi-Purpose Vehicle (MPV)"
        )
        XCTAssertEqual(VehicleBodyStyle.classify(identity: wrangler), .offRoadSUV)

        let crossover = VehicleIdentity(
            modelYear: 2019,
            make: "Honda",
            model: "CR-V",
            bodyClass: "Sport Utility Vehicle (SUV)/Multi-Purpose Vehicle (MPV)"
        )
        XCTAssertEqual(VehicleBodyStyle.classify(identity: crossover), .suv)
    }

    func testAGladiatorIsAPickupDespiteTheWranglerFamily() {
        let gladiator = VehicleIdentity(modelYear: 2021, make: "Jeep", model: "Gladiator")
        XCTAssertEqual(VehicleBodyStyle.classify(identity: gladiator), .pickup)
    }

    func testAnUnrecognisedShapeReturnsNilRatherThanASedan() {
        // Defaulting to a sedan would draw a saloon for a motorhome and look
        // like a considered answer. `nil` lets the caller show a neutral mark.
        let unknown = VehicleIdentity(modelYear: 2015, make: "Someone", model: "Something")
        XCTAssertNil(VehicleBodyStyle.classify(identity: unknown))
    }

    func testCommonBodyClassesMapToTheirShapes() {
        let cases: [(String, VehicleBodyStyle)] = [
            ("Sedan/Saloon", .sedan),
            ("Hatchback/Liftback/Notchback", .hatchback),
            ("Coupe", .coupe),
            ("Wagon", .wagon),
            ("Pickup", .pickup),
            ("Van", .van),
            ("Convertible/Cabriolet", .coupe)
        ]
        for (bodyClass, expected) in cases {
            let identity = VehicleIdentity(make: "Make", model: "Model", bodyClass: bodyClass)
            XCTAssertEqual(
                VehicleBodyStyle.classify(identity: identity), expected,
                "\(bodyClass) should classify as \(expected)"
            )
        }
    }

    // MARK: - Matched illustrations

    func testTheUnlimitedNamePicksTheFourDoorDrawing() {
        let identity = VehicleIdentity(
            modelYear: 2010, make: "Jeep", model: "Wrangler", trim: "Unlimited Sport"
        )
        XCTAssertEqual(VehicleIllustration.match(identity: identity), .jeepWranglerJKUnlimited)
    }

    func testAPlainWranglerPicksTheTwoDoorDrawing() {
        let identity = VehicleIdentity(modelYear: 2010, make: "Jeep", model: "Wrangler", trim: "Sport")
        XCTAssertEqual(VehicleIllustration.match(identity: identity), .jeepWranglerJKTwoDoor)
    }

    func testAWranglerOutsideTheJKYearsHasNoMatchedDrawing() {
        // A JL is a different vehicle. Offering the JK drawing for it would be
        // presenting a generation-wrong picture as an exact match.
        let jl = VehicleIdentity(modelYear: 2022, make: "Jeep", model: "Wrangler", trim: "Unlimited")
        XCTAssertNil(VehicleIllustration.match(identity: jl))
    }

    // MARK: - Resolution order

    func testAMatchedDrawingBeatsTheBodyStyleFallback() {
        let vehicle = Vehicle(
            identity: VehicleIdentity(modelYear: 2010, make: "Jeep", model: "Wrangler", trim: "Unlimited")
        )
        XCTAssertEqual(
            VehicleArtworkResolver.resolve(vehicle: vehicle, hasPhoto: false),
            .matchedIllustration(.jeepWranglerJKUnlimited)
        )
    }

    func testPhotoModeWithNoPhotoFallsThroughRatherThanShowingNothing() {
        // Choosing photo mode before taking a photo must not produce an empty
        // frame on every screen.
        let vehicle = Vehicle(
            identity: VehicleIdentity(modelYear: 2010, make: "Jeep", model: "Wrangler", trim: "Unlimited"),
            artwork: VehicleArtworkPreference(mode: .photo)
        )
        XCTAssertEqual(
            VehicleArtworkResolver.resolve(vehicle: vehicle, hasPhoto: false),
            .matchedIllustration(.jeepWranglerJKUnlimited)
        )
    }

    func testAnOwnerOverrideBeatsEverythingExceptTheirPhoto() {
        let vehicle = Vehicle(
            identity: VehicleIdentity(modelYear: 2010, make: "Jeep", model: "Wrangler", trim: "Unlimited"),
            artwork: VehicleArtworkPreference(bodyStyleOverride: .pickup)
        )
        XCTAssertEqual(
            VehicleArtworkResolver.resolve(vehicle: vehicle, hasPhoto: false),
            .bodyStyleIllustration(.pickup)
        )
    }

    func testAFallbackNeverDescribesItselfAsAnExactRendering() {
        let resolution = VehicleArtworkResolution.bodyStyleIllustration(.sedan)
        XCTAssertFalse(resolution.isExactMatch)
        XCTAssertTrue(resolution.disclosure.lowercased().contains("body style"))

        let matched = VehicleArtworkResolution.matchedIllustration(.jeepWranglerJKUnlimited)
        XCTAssertTrue(matched.isExactMatch)
        // Even the exact drawing says it is a drawing, and says it proves
        // nothing about fitment.
        XCTAssertTrue(matched.disclosure.lowercased().contains("not a photograph"))
        XCTAssertTrue(matched.disclosure.lowercased().contains("parts fit"))
    }

    // MARK: - Backward compatibility

    func testAVehicleWrittenBeforeBuildTwoStillDecodes() throws {
        // The shape a Build 1 backup or store row carries: no `artwork` key at
        // all. Swift's synthesised decoding treats a missing optional as nil,
        // which is exactly why this did not need a format-version bump.
        let json = """
        {
          "id": "11111111-1111-4111-8111-111111111111",
          "identity": { "make": "Jeep", "model": "Wrangler", "identityProvenance": "userEntered" },
          "configuration": { "powertrain": "gasoline", "transmission": "automatic",
                             "drivetrain": "fourWheelDrive", "camshaftDrive": "timingChain",
                             "transferCase": "fitted", "frontDifferential": "fitted",
                             "rearDifferential": "fitted", "market": "unitedStates",
                             "usageProfile": "normal", "confirmedFields": [] },
          "displayUnit": "miles",
          "odometerReplacements": [],
          "isDemo": false,
          "createdAt": "2024-01-01T00:00:00Z",
          "sortIndex": 0
        }
        """
        let decoder = CatalogLoader.makeDecoder()
        let vehicle = try decoder.decode(Vehicle.self, from: Data(json.utf8))
        XCTAssertNil(vehicle.artwork)
        // And it still resolves to something sensible.
        XCTAssertEqual(
            VehicleArtworkResolver.resolve(vehicle: vehicle, hasPhoto: false),
            .bodyStyleIllustration(.offRoadSUV)
        )
    }
}
