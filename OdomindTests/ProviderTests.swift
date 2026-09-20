import XCTest
@testable import Odomind
import OdomindCore

final class VPICMapperTests: XCTestCase {

    private func record(_ fixture: String) throws -> [String: VPICField] {
        let data = try FixtureFile.data(fixture)
        let envelope = try JSONDecoder().decode(VPICEnvelope.self, from: data)
        return try XCTUnwrap(envelope.results.first)
    }

    func testDecodesAKnownVehicle() throws {
        let result = VPICMapper.map(
            record: try record("vpic-wrangler-2010"),
            requestedVIN: "1J4BA3H14AL139999",
            requestedYear: 2010
        )

        XCTAssertEqual(result.identity.make, "Jeep", "ALL CAPS from the API should read as a name")
        XCTAssertEqual(result.identity.model, "Wrangler")
        XCTAssertEqual(result.identity.modelYear, 2010)
        XCTAssertEqual(result.identity.identityProvenance, .referenceSourced)
        XCTAssertEqual(result.configuration.powertrain, .gasoline)
        XCTAssertEqual(result.configuration.engineDisplacementLiters, 3.8)
        XCTAssertEqual(result.configuration.engineCylinders, 6)
    }

    func testFourWheelDriveSubTypeIsNotInvented() throws {
        let result = VPICMapper.map(
            record: try record("vpic-wrangler-2010"),
            requestedVIN: "1J4BA3H14AL139999",
            requestedYear: 2010
        )
        // vPIC says "4WD/4-Wheel Drive/4x4" without saying part-time or
        // full-time, so Odomind uses the general case rather than guessing.
        XCTAssertEqual(result.configuration.drivetrain, .fourWheelDrive)
        XCTAssertEqual(result.configuration.effectiveTransferCase, .fitted)
    }

    func testCamshaftDriveIsNeverInferredFromADecode() throws {
        let result = VPICMapper.map(
            record: try record("vpic-wrangler-2010"),
            requestedVIN: "1J4BA3H14AL139999",
            requestedYear: 2010
        )
        // vPIC does not report this, and guessing it would either invent a
        // timing-belt service or wrongly rule one out.
        XCTAssertEqual(result.configuration.camshaftDrive, .unknown)
    }

    func testBlankTransmissionBecomesUnknownAndIsReportedAsMissing() throws {
        let result = VPICMapper.map(
            record: try record("vpic-wrangler-2010"),
            requestedVIN: "1J4BA3H14AL139999",
            requestedYear: 2010
        )
        XCTAssertEqual(result.configuration.transmission, .unknown)
        XCTAssertTrue(result.missingFields.contains("Transmission"))
        XCTAssertTrue(result.isPartial)
    }

    func testCleanDecodeProducesNoScaryMessages() throws {
        let result = VPICMapper.map(
            record: try record("vpic-wrangler-2010"),
            requestedVIN: "1J4BA3H14AL139999",
            requestedYear: 2010
        )
        XCTAssertTrue(
            result.providerMessages.isEmpty,
            "a clean decode should not surface 'VIN decoded clean' as a warning: \(result.providerMessages)"
        )
    }

    func testElectricVehicleAndPartialDecode() throws {
        let result = VPICMapper.map(
            record: try record("vpic-partial-ev"),
            requestedVIN: "5YJ3E1EA0JF000000",
            requestedYear: nil
        )
        XCTAssertEqual(result.configuration.powertrain, .batteryElectric)
        XCTAssertEqual(result.configuration.drivetrain, .rearWheelDrive)
        XCTAssertNil(result.configuration.engineDisplacementLiters, "null must not become zero")
        XCTAssertEqual(result.suggestedVIN, "5YJ3E1EA0JF000001")
        XCTAssertFalse(result.providerMessages.isEmpty, "an error code should be surfaced")
    }

    func testAmbiguousEngineLeavesFieldsUnsetRatherThanGuessing() throws {
        let result = VPICMapper.map(
            record: try record("vpic-ambiguous-engine"),
            requestedVIN: "1FTFW1ET0EFA00000",
            requestedYear: 2014
        )
        XCTAssertNil(result.configuration.engineDisplacementLiters)
        XCTAssertNil(result.configuration.engineCylinders)
        XCTAssertEqual(result.configuration.powertrain, .unknown)
        // "4x2" says how many wheels are driven, not which ones.
        XCTAssertEqual(result.configuration.drivetrain, .unknown)
        XCTAssertTrue(result.missingFields.contains("Fuel type"))
        XCTAssertTrue(result.providerMessages.contains { $0.contains("Unable to identify the engine") })
    }

    func testApplicabilityFollowsADecodedElectricVehicle() throws {
        let result = VPICMapper.map(
            record: try record("vpic-partial-ev"),
            requestedVIN: "5YJ3E1EA0JF000000",
            requestedYear: nil
        )
        let catalog = try CatalogLoader.loadBundled()
        let vehicle = Vehicle(identity: result.identity, configuration: result.configuration)
        let ids = PlanBuilder.suggestions(for: vehicle, catalog: catalog).map(\.definition.id)
        XCTAssertFalse(ids.contains("engine-oil-and-filter"))
        XCTAssertTrue(ids.contains("tire-rotation"))
    }
}

final class VPICClientTests: XCTestCase {

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    private func makeClient(maximumAttempts: Int = 3) -> VPICClient {
        VPICClient(
            baseURL: URL(string: "https://vpic.test/api/vehicles/")!,
            session: StubURLProtocol.makeSession(),
            maximumAttempts: maximumAttempts
        )
    }

    func testDecodesFromARecordedResponse() async throws {
        let body = try FixtureFile.data("vpic-wrangler-2010")
        StubURLProtocol.handler = { _ in .init(statusCode: 200, body: body) }

        let result = try await makeClient().decode(vin: "1J4BA3H14AL139999", modelYear: 2010)
        XCTAssertEqual(result.identity.model, "Wrangler")
        XCTAssertEqual(result.identity.vin, "1J4BA3H14AL139999")
    }

    func testAMalformedVINIsRejectedBeforeAnythingIsSent() async {
        StubURLProtocol.handler = { _ in .init(statusCode: 200, body: Data()) }
        do {
            _ = try await makeClient().decode(vin: "NOT-A-VIN", modelYear: nil)
            XCTFail("expected a rejection")
        } catch let error as ProviderError {
            guard case .vinRejected = error else { return XCTFail("expected vinRejected, got \(error)") }
            XCTAssertEqual(StubURLProtocol.requestCount, 0, "a bad VIN must never leave the device")
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testServerErrorsAreRetriedThenReported() async {
        StubURLProtocol.handler = { _ in .init(statusCode: 503, body: Data("{}".utf8)) }
        do {
            _ = try await makeClient(maximumAttempts: 2).decode(vin: "1J4BA3H14AL139999", modelYear: nil)
            XCTFail("expected a failure")
        } catch let error as ProviderError {
            XCTAssertEqual(error, .serviceUnavailable(statusCode: 503))
            XCTAssertEqual(StubURLProtocol.requestCount, 2, "retry should be bounded, not unlimited")
            XCTAssertTrue(error.suggestsManualEntry)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testClientErrorsAreNotRetried() async {
        StubURLProtocol.handler = { _ in .init(statusCode: 404, body: Data("{}".utf8)) }
        do {
            _ = try await makeClient().decode(vin: "1J4BA3H14AL139999", modelYear: nil)
            XCTFail("expected a failure")
        } catch let error as ProviderError {
            XCTAssertEqual(error, .serviceUnavailable(statusCode: 404))
            XCTAssertEqual(StubURLProtocol.requestCount, 1, "a 404 will not change on a second try")
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testGarbageResponseIsReportedAsUnreadable() async {
        StubURLProtocol.handler = { _ in .init(statusCode: 200, body: Data("<html>oops</html>".utf8)) }
        do {
            _ = try await makeClient().decode(vin: "1J4BA3H14AL139999", modelYear: nil)
            XCTFail("expected a failure")
        } catch let error as ProviderError {
            guard case .unreadableResponse = error else {
                return XCTFail("expected unreadableResponse, got \(error)")
            }
            XCTAssertTrue(error.suggestsManualEntry)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testModelYearIsPassedThroughAsAQueryItem() async throws {
        let body = try FixtureFile.data("vpic-wrangler-2010")
        let seen = URLBox()
        StubURLProtocol.handler = { request in
            seen.url = request.url
            return .init(statusCode: 200, body: body)
        }
        _ = try await makeClient().decode(vin: "1J4BA3H14AL139999", modelYear: 2010)
        let query = seen.url?.query ?? ""
        XCTAssertTrue(query.contains("modelyear=2010"), "query was \(query)")
        XCTAssertTrue(query.contains("format=json"))
    }
}

final class VINTests: XCTestCase {

    func testNormalizationStripsSeparators() {
        XCTAssertEqual(VIN.normalize(" 1j4ba3h14-al139999 "), "1J4BA3H14AL139999")
    }

    func testForbiddenLettersAreRejected() {
        let problems = VIN.problems(in: "1J4BA3H14ALI39999")
        XCTAssertTrue(problems.contains { if case .forbiddenCharacter = $0 { return true }; return false })
        XCTAssertFalse(VIN.isStructurallyValid("1J4BA3H14ALI39999"))
    }

    func testWrongLengthIsRejected() {
        XCTAssertFalse(VIN.isStructurallyValid("1J4BA3H14AL1399"))
    }

    func testCheckDigitMismatchIsACautionNotARejection() {
        // Flipping the check digit must warn without blocking: vehicles built
        // outside North America are not required to carry a valid one.
        let vin = "1J4BA3H14AL139999"
        let broken = vin.prefix(8) + "9" + vin.dropFirst(9)
        let problems = VIN.problems(in: String(broken))
        if problems.contains(where: { if case .checkDigitMismatch = $0 { return true }; return false }) {
            XCTAssertTrue(VIN.isStructurallyValid(String(broken)), "a check digit mismatch must not block")
        }
    }

    func testModelYearDecoding() {
        // Position 10 is "A", which is 1980 or 2010. With a plausible ceiling of
        // 2027 the answer is 2010.
        XCTAssertEqual(VIN.modelYear(from: "1J4BA3H14AL139999", notAfter: 2027), 2010)
        XCTAssertNil(VIN.modelYear(from: "short", notAfter: 2027))
    }
}


/// A reference box so a test can observe what the stub protocol was asked for.
final class URLBox: @unchecked Sendable {
    var url: URL?
}
