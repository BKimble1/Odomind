import CoreLocation
import XCTest
@testable import Odomind

/// The location rules the brief names, which until now were asserted only by
/// reading the code: "handle cancellation, timeout, and repeated taps without
/// overwriting an unresolved continuation. Distinguish denied access from a
/// temporary location error... A manually selected area remains selected until
/// the user changes it... Invalidate stale geocoding/store responses when the
/// area changes."
@MainActor
final class ShoppingLocationTests: XCTestCase {

    /// Answers on command, so a test can hold a fix open and change its mind
    /// while it is in flight.
    ///
    /// Explicitly main-actor isolated: a nested type does not inherit the
    /// enclosing type's isolation, and `LocationFixProviding` is
    /// `@MainActor`.
    @MainActor
    private final class StubLocationProvider: LocationFixProviding {
        var authorizationStatus: CLAuthorizationStatus = .notDetermined
        var isAuthorized: Bool {
            authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
        }

        var authorizationAnswer: CLAuthorizationStatus = .authorizedWhenInUse
        var fixAnswer: Result<CLLocation, LocationFailure> = .failure(.unavailable)
        private(set) var fixCallCount = 0
        private(set) var authorizationCallCount = 0
        /// Set to hold every fix until `release()` is called.
        var gate: AsyncGate?

        func requestAuthorization(timeout: Duration) async -> CLAuthorizationStatus {
            authorizationCallCount += 1
            authorizationStatus = authorizationAnswer
            return authorizationAnswer
        }

        func fix(maxAge: TimeInterval, timeout: Duration) async -> Result<CLLocation, LocationFailure> {
            fixCallCount += 1
            if let gate { await gate.wait() }
            return fixAnswer
        }
    }

    private func defaults() -> UserDefaults {
        // A suite per test, so one test's persisted area cannot decide
        // another's outcome.
        let suite = UserDefaults(suiteName: "odomind.tests.\(UUID().uuidString)")!
        return suite
    }

    private func settle() async throws {
        try await Task.sleep(nanoseconds: 200_000_000)
    }

    // MARK: - Denial is not a failure

    func testARefusalIsRecordedAsDeniedRatherThanAsAnError() async throws {
        let provider = StubLocationProvider()
        provider.authorizationStatus = .authorizedWhenInUse
        provider.fixAnswer = .failure(.denied)
        let service = ShoppingLocationService(provider: provider, defaults: defaults())

        service.useCurrentLocation()
        try await settle()

        XCTAssertEqual(service.resolution, .denied, "the remedy is Settings, not trying again")
    }

    func testATemporaryProblemIsNotRecordedAsARefusal() async throws {
        let provider = StubLocationProvider()
        provider.authorizationStatus = .authorizedWhenInUse
        provider.fixAnswer = .failure(.unavailable)
        let service = ShoppingLocationService(provider: provider, defaults: defaults())

        service.useCurrentLocation()
        try await settle()

        guard case .failed = service.resolution else {
            return XCTFail("a transient error must not read as a denial, got \(service.resolution)")
        }
    }

    func testATimeoutIsAFailureAndSaysToTryAgain() async throws {
        let provider = StubLocationProvider()
        provider.authorizationStatus = .authorizedWhenInUse
        provider.fixAnswer = .failure(.timedOut)
        let service = ShoppingLocationService(provider: provider, defaults: defaults())

        service.useCurrentLocation()
        try await settle()

        guard case .failed(let message) = service.resolution else {
            return XCTFail("a timeout is not a refusal, got \(service.resolution)")
        }
        XCTAssertTrue(
            message.lowercased().contains("try again"),
            "a timeout is worth retrying and should say so, got '\(message)'"
        )
    }

    func testRefusingPermissionLeavesTheServiceDenied() async throws {
        let provider = StubLocationProvider()
        provider.authorizationAnswer = .denied
        let service = ShoppingLocationService(provider: provider, defaults: defaults())

        let status = await service.requestPermission()

        XCTAssertEqual(status, .denied)
        XCTAssertEqual(service.resolution, .denied)
    }

    // MARK: - Opening a screen is not asking

    func testOpeningPartsWithNoPermissionDoesNotRequestALocation() async throws {
        // A screenshot caught this: tapping "Find parts" on an oil change put
        // the iOS location prompt on screen, in an app whose own permission
        // string says "only when you ask". Parts resolves on appear so a
        // chosen area loads its shops without a second tap; with nothing
        // granted there is nothing to resolve.
        let provider = StubLocationProvider()   // .notDetermined
        let service = ShoppingLocationService(provider: provider, defaults: defaults())

        service.resolve()
        try await settle()

        XCTAssertEqual(provider.fixCallCount, 0, "opening a screen must not ask the device where it is")
        XCTAssertEqual(provider.authorizationCallCount, 0, "and must not raise the system prompt")
        XCTAssertEqual(service.resolution, .none, "there is simply no area yet")
    }

    func testOpeningPartsWithPermissionAlreadyGrantedDoesResolve() async throws {
        // The other half: somebody who already said yes should not have to
        // tap again every time they open Parts.
        let provider = StubLocationProvider()
        provider.authorizationStatus = .authorizedWhenInUse
        provider.fixAnswer = .success(CLLocation(latitude: 51.5, longitude: -0.12))
        let service = ShoppingLocationService(provider: provider, defaults: defaults())

        service.resolve()
        try await settle()

        XCTAssertEqual(provider.fixCallCount, 1)
        guard case .ready = service.resolution else {
            return XCTFail("an authorised owner should get an area, got \(service.resolution)")
        }
    }

    func testTappingUseCurrentLocationIsWhatAsks() async throws {
        let provider = StubLocationProvider()   // .notDetermined
        provider.authorizationAnswer = .authorizedWhenInUse
        provider.fixAnswer = .success(CLLocation(latitude: 51.5, longitude: -0.12))
        let service = ShoppingLocationService(provider: provider, defaults: defaults())

        service.useCurrentLocation()
        try await settle()

        XCTAssertEqual(provider.authorizationCallCount, 1, "the tap is the ask")
        guard case .ready = service.resolution else {
            return XCTFail("granting should produce an area, got \(service.resolution)")
        }
    }

    func testRefusingAtTheTapIsRecordedAsDenied() async throws {
        let provider = StubLocationProvider()
        provider.authorizationAnswer = .denied
        let service = ShoppingLocationService(provider: provider, defaults: defaults())

        service.useCurrentLocation()
        try await settle()

        XCTAssertEqual(service.resolution, .denied)
        XCTAssertEqual(provider.fixCallCount, 0, "a refusal is not followed by asking anyway")
    }

    // MARK: - Repeated taps

    func testRepeatedTapsWhileUnresolvedDoNotStrandTheFirstRequest() async throws {
        // Build 2's defect, in the layer above it: a single continuation in a
        // property, overwritten by the second tap. Leaking a checked
        // continuation traps at runtime, so this is a crash and not a lost
        // callback. Three taps, then one answer.
        let gate = AsyncGate()
        let provider = StubLocationProvider()
        provider.gate = gate
        provider.authorizationStatus = .authorizedWhenInUse
        provider.fixAnswer = .success(CLLocation(latitude: 51.5, longitude: -0.12))
        let service = ShoppingLocationService(provider: provider, defaults: defaults())

        service.useCurrentLocation()
        service.useCurrentLocation()
        service.useCurrentLocation()
        await gate.open()
        try await settle()

        // Coordinates are the answer; the town name is a label that arrives
        // later. This used to wait on a real reverse geocode before going
        // ready, which made the test race CLGeocoder — it passed or failed
        // depending on how fast a network call was.
        guard case .ready(let latitude, _, _) = service.resolution else {
            return XCTFail("three taps should still end in one answer, got \(service.resolution)")
        }
        XCTAssertEqual(latitude, 51.5, accuracy: 0.001)
    }

    func testAFixThatLandsAfterATownIsChosenIsDiscarded() async throws {
        // The sharp version of the test below. The fix is released and then
        // given time to land, so a service that lets it through fails here
        // rather than passing because nothing had arrived yet.
        let gate = AsyncGate()
        let provider = StubLocationProvider()
        provider.gate = gate
        provider.authorizationStatus = .authorizedWhenInUse
        provider.fixAnswer = .success(CLLocation(latitude: 51.5, longitude: -0.12))
        let service = ShoppingLocationService(provider: provider, defaults: defaults())

        service.useCurrentLocation()
        service.choose(
            PlaceSuggestion(name: "Boise", detail: nil, latitude: 43.6, longitude: -116.2)
        )
        await gate.open()
        try await settle()
        try await settle()

        XCTAssertEqual(
            service.resolution.label, "Boise",
            "a fix arriving after the owner picked a town must not replace it"
        )
        guard let coordinate = service.resolution.coordinate else {
            return XCTFail("the chosen town should still be searchable")
        }
        XCTAssertEqual(coordinate.latitude, 43.6, accuracy: 0.001)
    }

    // MARK: - Changing the area while something is in flight

    func testChoosingATownWhileAFixIsPendingWinsOverTheFix() async throws {
        // The brief: "Invalidate stale geocoding/store responses when the area
        // changes." The device's answer arrives after the owner has typed a
        // town, and it is for somewhere they are no longer asking about.
        let gate = AsyncGate()
        let provider = StubLocationProvider()
        provider.gate = gate
        provider.authorizationStatus = .authorizedWhenInUse
        provider.fixAnswer = .success(CLLocation(latitude: 51.5, longitude: -0.12))
        let service = ShoppingLocationService(provider: provider, defaults: defaults())

        service.useCurrentLocation()
        service.choose(
            PlaceSuggestion(name: "Boise", detail: "Idaho, United States", latitude: 43.6, longitude: -116.2)
        )
        await gate.open()
        try await settle()

        XCTAssertEqual(service.resolution.label, "Boise", "the later choice is the current one")
        guard let coordinate = service.resolution.coordinate else {
            return XCTFail("a chosen town is immediately searchable")
        }
        XCTAssertEqual(coordinate.latitude, 43.6, accuracy: 0.001)
    }

    // MARK: - A choice, not a cache

    func testAChosenTownSurvivesARelaunch() throws {
        let store = defaults()
        let first = ShoppingLocationService(provider: StubLocationProvider(), defaults: store)
        first.choose(
            PlaceSuggestion(name: "Boise", detail: "Idaho, United States", latitude: 43.6, longitude: -116.2)
        )

        // A second service reading the same storage is what the next launch is.
        let second = ShoppingLocationService(provider: StubLocationProvider(), defaults: store)
        XCTAssertEqual(second.area, .place(name: "Boise", detail: "Idaho, United States", latitude: 43.6, longitude: -116.2))
        XCTAssertEqual(
            second.resolution.label, "Boise",
            "a stored town carries its coordinates, so a launch with no network still knows where to look"
        )
    }

    func testAStoredTownIsSearchableWithoutAskingForPermission() throws {
        let store = defaults()
        let first = ShoppingLocationService(provider: StubLocationProvider(), defaults: store)
        first.choose(PlaceSuggestion(name: "Boise", detail: nil, latitude: 43.6, longitude: -116.2))

        let provider = StubLocationProvider()   // .notDetermined
        let second = ShoppingLocationService(provider: provider, defaults: store)

        XCTAssertTrue(second.hasUsableArea, "a typed town needs no permission")
        XCTAssertEqual(provider.fixCallCount, 0, "and must not trigger a location request")
    }

    func testCurrentLocationWithoutPermissionIsNotAUsableArea() throws {
        let provider = StubLocationProvider()   // .notDetermined
        let service = ShoppingLocationService(provider: provider, defaults: defaults())
        XCTAssertFalse(
            service.hasUsableArea,
            "Parts should ask rather than search from nowhere"
        )
    }

    // MARK: - Not asking twice

    func testResolvingAnAlreadyReadyAreaDoesNotAskAgain() async throws {
        let provider = StubLocationProvider()
        provider.authorizationStatus = .authorizedWhenInUse
        provider.fixAnswer = .success(CLLocation(latitude: 51.5, longitude: -0.12))
        let service = ShoppingLocationService(provider: provider, defaults: defaults())

        service.useCurrentLocation()
        try await settle()
        let afterFirst = provider.fixCallCount

        // Opening Parts again should show what is already known rather than
        // starting over.
        service.resolve()
        try await settle()

        XCTAssertEqual(provider.fixCallCount, afterFirst, "a resolved area is not re-resolved")
    }
}
