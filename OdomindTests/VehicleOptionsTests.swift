import XCTest
@testable import Odomind
@testable import OdomindCore

/// The setup step's configuration options, and the race the brief names:
/// "Test changing the selected vehicle after VIN decoding: stale
/// VIN/configuration/parts/photo data cannot attach to the new car."
@MainActor
final class VehicleOptionsTests: XCTestCase {

    private func option(
        id: String,
        label: String,
        drive: String? = nil,
        fuel: String? = "Regular Gasoline"
    ) -> VehicleConfigurationOption {
        VehicleConfigurationOption(
            id: id,
            providerName: "Stub configuration provider",
            providerKey: "stub",
            label: label,
            driveDescription: drive,
            fuelDescription: fuel,
            retrievedOn: Date(timeIntervalSince1970: 1_780_000_000)
        )
    }

    // MARK: - The ordinary path

    func testOptionsAreOfferedForAVehicleTheProviderKnows() async throws {
        var provider = StubConfigurationOptionProvider()
        provider.answer = [
            option(id: "1", label: "3.8 L, 6 cyl, Automatic 4-spd", drive: "Part-time 4-Wheel Drive"),
            option(id: "2", label: "3.8 L, 6 cyl, Manual 6-spd", drive: "Part-time 4-Wheel Drive"),
        ]
        let service = VehicleOptionsService(provider: provider)

        service.resolve(modelYear: 2010, make: "Jeep", model: "Wrangler")
        try await settle()

        XCTAssertEqual(service.status.options.count, 2)
        XCTAssertNil(service.selectedOptionID, "two options is a question, not an answer")
    }

    func testASingleConfigurationIsNotPresentedAsAChoice() async throws {
        var provider = StubConfigurationOptionProvider()
        provider.answer = [option(id: "9", label: "2.0 L, 4 cyl, Automatic (S8)")]
        let service = VehicleOptionsService(provider: provider)

        service.resolve(modelYear: 2019, make: "Ford", model: "Ranger")
        try await settle()

        XCTAssertEqual(service.selectedOptionID, "9", "there is nothing to choose between")
    }

    // MARK: - Absence, said plainly

    func testNoPublishedConfigurationsFallsBackWithAReason() async throws {
        let service = VehicleOptionsService(provider: StubConfigurationOptionProvider())

        service.resolve(modelYear: 1971, make: "Datsun", model: "510")
        try await settle()

        guard case .none(let reason) = service.status else {
            return XCTFail("expected an explained absence, got \(service.status)")
        }
        XCTAssertFalse(reason.isEmpty)
    }

    func testAProviderOutageIsAnAbsenceRatherThanASpinnerForever() async throws {
        var provider = StubConfigurationOptionProvider()
        provider.error = .notConnected
        let service = VehicleOptionsService(provider: provider)

        service.resolve(modelYear: 2010, make: "Jeep", model: "Wrangler")
        try await settle()

        guard case .none = service.status else {
            return XCTFail("expected an absence, got \(service.status)")
        }
    }

    func testAVehicleWithNoYearIsNotAskedAbout() {
        let service = VehicleOptionsService(provider: StubConfigurationOptionProvider())
        service.resolve(modelYear: nil, make: "Jeep", model: "Wrangler")

        guard case .none = service.status else {
            return XCTFail("a yearless vehicle cannot be looked up, got \(service.status)")
        }
    }

    // MARK: - The race

    func testAnAnswerForTheFirstVehicleCannotLandOnTheSecond() async throws {
        // The provider is held open, the owner changes their mind, and only
        // then does the first answer come back. It is for a car that is no
        // longer on screen.
        let gate = AsyncGate()
        var provider = StubConfigurationOptionProvider()
        provider.gate = gate
        // Only the Jeep is answered, so anything that turns up for the Camry
        // can only have come from the Jeep's request.
        provider.onlyForMake = "Jeep"
        provider.answer = [option(id: "jeep-1", label: "3.8 L, 6 cyl, Automatic 4-spd")]
        let service = VehicleOptionsService(provider: provider)

        service.resolve(modelYear: 2010, make: "Jeep", model: "Wrangler")
        service.resolve(modelYear: 2015, make: "Toyota", model: "Camry")
        await gate.open()
        try await settle()

        XCTAssertTrue(
            service.status.options.isEmpty,
            "the Jeep's engines must not be offered for the Camry, got \(service.status)"
        )
    }

    func testAskingAboutTheSameVehicleTwiceDoesNotStartAgain() async throws {
        var provider = StubConfigurationOptionProvider()
        provider.answer = [
            option(id: "1", label: "3.8 L, 6 cyl, Automatic 4-spd"),
            option(id: "2", label: "3.8 L, 6 cyl, Manual 6-spd"),
        ]
        let service = VehicleOptionsService(provider: provider)

        service.resolve(modelYear: 2010, make: "Jeep", model: "Wrangler")
        try await settle()
        service.selectedOptionID = "2"

        // Spelled differently, same vehicle. Re-resolving would throw away
        // what the owner just picked.
        service.resolve(modelYear: 2010, make: "JEEP", model: "wrangler")
        XCTAssertEqual(service.selectedOptionID, "2")
    }

    func testLeavingTheScreenInvalidatesWhatIsInFlight() async throws {
        let gate = AsyncGate()
        var provider = StubConfigurationOptionProvider()
        provider.gate = gate
        provider.answer = [option(id: "1", label: "3.8 L, 6 cyl, Automatic 4-spd")]
        let service = VehicleOptionsService(provider: provider)

        service.resolve(modelYear: 2010, make: "Jeep", model: "Wrangler")
        service.cancel()
        await gate.open()
        try await settle()

        XCTAssertTrue(service.status.options.isEmpty, "got \(service.status)")
    }

    /// Lets the detached provider task run and its answer come back.
    private func settle() async throws {
        try await Task.sleep(nanoseconds: 200_000_000)
    }
}
