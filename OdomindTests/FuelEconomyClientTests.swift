import XCTest
import OdomindCore
@testable import Odomind

/// The configuration provider Build 3's setup step is built on.
///
/// It had no tests. Both of the bugs it has produced so far were the same
/// bug — two services spelling the same car differently — and neither was
/// caught here: the model-name mismatch came out of a probe log, and the
/// make-name mismatch out of a screenshot showing "JEEP Wrangler" beside a
/// line saying nothing was published for it. These pin the behaviour so the
/// third one does not need a runner to find.
///
/// Every response is served from a stub. A test that reaches
/// fueleconomy.gov is a test that fails on a train.
final class FuelEconomyClientTests: XCTestCase {

    /// Every URL the client asked for, in order.
    nonisolated(unsafe) private static var asked: [URL] = []

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        Self.asked = []
    }

    override func tearDown() {
        StubURLProtocol.reset()
        Self.asked = []
        super.tearDown()
    }

    // MARK: - The service, stood in for

    private func makeClient(maximumDetailed: Int = 8) -> FuelEconomyClient {
        FuelEconomyClient(
            baseURL: URL(string: "https://fueleconomy.test/ws/rest/")!,
            session: StubURLProtocol.makeSession(),
            maximumDetailed: maximumDetailed
        )
    }

    /// Answers the three menu endpoints and the detail endpoint, in the
    /// shapes the real service uses.
    private func serve(
        makes: [String],
        models: [String],
        optionsByModel: [String: [(text: String, value: String)]] = [:],
        detail: [String: String] = [:]
    ) {
        StubURLProtocol.handler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            Self.asked.append(url)

            func menu(_ pairs: [(text: String, value: String)]) throws -> StubURLProtocol.Response {
                let items = pairs.map { ["text": $0.text, "value": $0.value] }
                let body = try JSONSerialization.data(withJSONObject: ["menuItem": items])
                return .init(statusCode: 200, body: body)
            }

            let path = url.path
            if path.hasSuffix("menu/make") {
                return try menu(makes.map { (text: $0, value: $0) })
            }
            if path.hasSuffix("menu/model") {
                return try menu(models.map { (text: $0, value: $0) })
            }
            if path.hasSuffix("menu/options") {
                let wanted = Self.value(of: "model", in: url) ?? ""
                return try menu(optionsByModel[wanted] ?? [])
            }
            let body = try JSONSerialization.data(withJSONObject: detail)
            return .init(statusCode: 200, body: body)
        }
    }

    private static func value(of name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == name }?
            .value
    }

    private func requests(endingIn suffix: String) -> [URL] {
        Self.asked.filter { $0.path.hasSuffix(suffix) }
    }

    // MARK: - Two vocabularies, both directions

    func testTheServicesOwnSpellingOfTheMakeIsUsed() async throws {
        // vPIC answers "JEEP", in capitals, and that is what Odomind carries
        // on the vehicle because it is what the source said. This service
        // says "Jeep", and answers a make it does not recognise with an empty
        // model menu — which reads as "nothing published for this vehicle".
        serve(
            makes: ["Ford", "Jeep", "Toyota"],
            models: ["Wrangler 4WD"],
            optionsByModel: ["Wrangler 4WD": [(text: "Auto 4-spd", value: "26425")]]
        )

        let found = try await makeClient().options(modelYear: 2010, make: "JEEP", model: "Wrangler")

        XCTAssertEqual(found.count, 1, "a Jeep spelled the way vPIC spells it must still find its configurations")
        let modelRequests = requests(endingIn: "menu/model")
        XCTAssertEqual(modelRequests.count, 1)
        XCTAssertEqual(
            Self.value(of: "make", in: modelRequests[0]),
            "Jeep",
            "the make has to go out in this service's spelling, not vPIC's"
        )
        let optionsRequest = try XCTUnwrap(requests(endingIn: "menu/options").first)
        XCTAssertEqual(
            Self.value(of: "make", in: optionsRequest),
            "Jeep",
            "and in every request after it"
        )
    }

    func testAMakeTheServiceDoesNotListIsStillAskedAbout() async throws {
        // A make this service has never heard of is a real answer — an
        // import, or something too new for the menu — and it should produce a
        // request and an honest empty result, not an error about spelling.
        serve(makes: ["Ford", "Toyota"], models: [])

        let found = try await makeClient().options(modelYear: 2023, make: "Bollinger", model: "B1")

        XCTAssertTrue(found.isEmpty)
        let modelRequests = requests(endingIn: "menu/model")
        XCTAssertEqual(modelRequests.count, 1, "an unlisted make must not skip the lookup")
        XCTAssertEqual(Self.value(of: "make", in: modelRequests[0]), "Bollinger")
    }

    func testBothOfTheServicesNamesForOneModelAreOffered() async throws {
        // vPIC says "Wrangler". This service splits it by drivetrain, and the
        // two are different cars for Odomind's purposes: one has a transfer
        // case and one does not.
        serve(
            makes: ["Jeep"],
            models: ["Wrangler 2WD", "Wrangler 4WD"],
            optionsByModel: [
                "Wrangler 2WD": [(text: "Auto 4-spd", value: "26424")],
                "Wrangler 4WD": [(text: "Auto 4-spd", value: "26425")],
            ]
        )

        let found = try await makeClient().options(modelYear: 2010, make: "Jeep", model: "Wrangler")

        XCTAssertEqual(found.count, 2)
        XCTAssertEqual(Set(found.map(\.id)).count, 2, "two configurations must not share one identifier")
        XCTAssertEqual(
            Set(found.map(\.label)),
            ["Wrangler 2WD — Auto 4-spd", "Wrangler 4WD — Auto 4-spd"],
            "an owner cannot choose between two rows that read the same"
        )
    }

    func testAnExactModelNameWinsOverThePrefixMatches() async throws {
        // "Camry" is a name this service uses, so the hybrid and the Solara
        // are not offered alongside it. Only where there is no exact name do
        // the prefix matches stand in for one.
        serve(
            makes: ["Toyota"],
            models: ["Camry", "Camry Hybrid", "Camry Solara"],
            optionsByModel: ["Camry": [(text: "Automatic (S6)", value: "34567")]]
        )

        let found = try await makeClient().options(modelYear: 2015, make: "Toyota", model: "Camry")

        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(
            found[0].label,
            "Automatic (S6)",
            "one unambiguous name needs no disambiguating prefix, and the label is the provider's own words"
        )
    }

    // MARK: - Absence, and what is made of a detail

    func testNothingPublishedIsAnEmptyAnswerRatherThanAnError() async throws {
        serve(makes: ["Jeep"], models: [])

        let found = try await makeClient().options(modelYear: 1994, make: "Jeep", model: "Wrangler")

        XCTAssertTrue(
            found.isEmpty,
            "a vehicle older than the service's data is a gap to say out loud, not a failure"
        )
    }

    func testTheDetailIsMappedOntoOdomindsOwnConfiguration() async throws {
        serve(
            makes: ["Jeep"],
            models: ["Wrangler 4WD"],
            optionsByModel: ["Wrangler 4WD": [(text: "Auto 4-spd", value: "26425")]],
            detail: [
                "displ": "3.8",
                "cylinders": "6",
                "trany": "Automatic 4-spd",
                "drive": "Part-time 4-Wheel Drive",
                "fuelType": "Regular Gasoline",
                "VClass": "Special Purpose Vehicle 4WD",
            ]
        )

        let found = try await makeClient().options(modelYear: 2010, make: "JEEP", model: "Wrangler")
        let option = try XCTUnwrap(found.first)

        XCTAssertEqual(option.id, "26425")
        XCTAssertEqual(option.providerKey, FuelEconomyClient.providerKey)
        XCTAssertEqual(option.engineDisplacementLiters, 3.8)
        XCTAssertEqual(option.cylinders, 6)
        // "Regular" is this service naming the grade, not the fuel.
        XCTAssertEqual(option.powertrain, .gasoline)
        XCTAssertEqual(option.drivetrain, .fourWheelDrivePartTime)
        XCTAssertEqual(option.transmission, .automatic)
        XCTAssertEqual(option.vehicleClass, "Special Purpose Vehicle 4WD")
    }

    func testADetailThatFailsStillLeavesAChoosableOption() async throws {
        // The label is what the owner reads and recognises. Losing the engine
        // facts is a worse answer; losing the row is a screen with nothing on
        // it.
        StubURLProtocol.handler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            Self.asked.append(url)
            func menu(_ pairs: [(String, String)]) throws -> StubURLProtocol.Response {
                let items = pairs.map { ["text": $0.0, "value": $0.1] }
                let body = try JSONSerialization.data(withJSONObject: ["menuItem": items])
                return .init(statusCode: 200, body: body)
            }
            let path = url.path
            if path.hasSuffix("menu/make") { return try menu([("Jeep", "Jeep")]) }
            if path.hasSuffix("menu/model") { return try menu([("Wrangler 4WD", "Wrangler 4WD")]) }
            if path.hasSuffix("menu/options") { return try menu([("Auto 4-spd", "26425")]) }
            return .init(statusCode: 500, body: Data())
        }

        let found = try await makeClient().options(modelYear: 2010, make: "Jeep", model: "Wrangler")
        let option = try XCTUnwrap(found.first)

        XCTAssertEqual(option.label, "Auto 4-spd")
        XCTAssertNil(option.engineDisplacementLiters)
        XCTAssertEqual(option.powertrain, .unknown, "an unstated fuel stays unstated rather than becoming petrol")
    }
}
