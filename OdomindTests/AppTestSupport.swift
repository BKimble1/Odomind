import Foundation
import XCTest
@testable import Odomind
import OdomindCore

// Shared helpers for the app-level tests.
//
// Everything runs against an in-memory store, a temporary attachments
// directory and a fake notification scheduler, so a test never touches the
// simulator's real data and never depends on notification permission.

extension Calendar {
    static func fixedUTC() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }
}

func appDate(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    guard let date = Calendar.fixedUTC().date(from: components) else {
        fatalError("could not build test date")
    }
    return date
}

@MainActor
enum AppFixture {
    /// A model wired entirely to test doubles.
    static func makeModel(
        now: Date = appDate(2026, 6, 15),
        scheduler: InMemoryNotificationScheduler = InMemoryNotificationScheduler(),
        provider: VehicleIdentificationProvider = StubIdentificationProvider()
    ) throws -> (model: AppModel, scheduler: InMemoryNotificationScheduler, attachmentsDirectory: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OdomindTests-\(UUID().uuidString)", isDirectory: true)
        let attachments = try AttachmentStore(directory: directory)
        let store = try OdomindStore(inMemory: true)
        let model = AppModel(
            store: store,
            catalogService: CatalogService(),
            attachments: attachments,
            notificationScheduler: scheduler,
            identificationProvider: provider,
            clock: FixedClock(now)
        )
        model.refresh()
        return (model, scheduler, directory)
    }

    static func draft(
        make: String = "Jeep",
        model: String = "Wrangler",
        year: Int = 2010,
        odometer: Int? = 120_000,
        unit: DistanceUnit = .miles,
        taskIDs: Set<String> = ["engine-oil-and-filter", "tire-rotation"],
        now: Date = appDate(2026, 6, 15)
    ) -> VehicleDraft {
        var draft = VehicleDraft()
        draft.identity = VehicleIdentity(modelYear: year, make: make, model: model)
        draft.configuration = VehicleConfiguration(
            powertrain: .gasoline,
            engineDisplacementLiters: 3.8,
            transmission: .automatic,
            drivetrain: .fourWheelDrivePartTime,
            camshaftDrive: .timingChain,
            market: .unitedStates
        )
        draft.displayUnit = unit
        draft.odometerAmount = odometer
        draft.odometerDate = now
        draft.selectedTaskIDs = taskIDs
        return draft
    }
}

/// A provider that answers from a canned result rather than the network.
struct StubIdentificationProvider: VehicleIdentificationProvider {
    var displayName = "Stub provider"
    var contactedHost = "example.invalid"
    var result: VehicleDecodeResult?
    var error: ProviderError?

    func decode(vin: String, modelYear: Int?) async throws -> VehicleDecodeResult {
        if let error { throw error }
        if let result { return result }
        throw ProviderError.notConnected
    }

    func models(make: String, modelYear: Int) async throws -> [String] {
        if let error { throw error }
        return []
    }

    /// Also throws. Without this the yearless path would quietly take the
    /// protocol's default and an outage would look like "no such model".
    func models(make: String) async throws -> [String] {
        if let error { throw error }
        return []
    }
}

/// Serves recorded responses to `URLSession` so provider tests never touch the
/// network. Core tests must pass with the machine in airplane mode.
final class StubURLProtocol: URLProtocol {
    struct Response {
        var statusCode: Int
        var body: Data
    }

    nonisolated(unsafe) static var handler: ((URLRequest) throws -> Response)?
    nonisolated(unsafe) static var requestCount = 0

    static func reset() {
        handler = nil
        requestCount = 0
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        StubURLProtocol.requestCount += 1
        guard let handler = StubURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let response = try handler(request)
            let http = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.invalid")!,
                statusCode: response.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: response.body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

enum FixtureFile {
    /// Loads a recorded provider response from the test bundle.
    static func data(_ name: String) throws -> Data {
        let bundle = Bundle(for: FixtureBundleToken.self)
        guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
            ?? bundle.url(forResource: name, withExtension: "json") else {
            throw XCTSkip("Fixture \(name).json is not in the test bundle")
        }
        return try Data(contentsOf: url)
    }
}

final class FixtureBundleToken {}

/// A provider that answers on command, so the search model's ordering
/// behaviour can be driven deliberately rather than raced against a real
/// network.
///
/// Each call parks a continuation keyed by the make it was asked about; the
/// test decides which one answers, and in which order.
actor ScriptedModelProvider: VehicleIdentificationProvider {
    nonisolated var displayName: String { "Scripted provider" }
    nonisolated var contactedHost: String { "example.invalid" }

    private var waiting: [String: CheckedContinuation<[String], Error>] = [:]
    private var calls: [String] = []

    nonisolated func decode(vin: String, modelYear: Int?) async throws -> VehicleDecodeResult {
        throw ProviderError.notConnected
    }

    nonisolated func models(make: String, modelYear: Int) async throws -> [String] {
        try await park(make: make)
    }

    /// The yearless call Build 3 added. Parked under the same key, because
    /// which make was asked about is what a test is steering.
    nonisolated func models(make: String) async throws -> [String] {
        try await park(make: make)
    }

    private func park(make: String) async throws -> [String] {
        calls.append(make)
        return try await withCheckedThrowingContinuation { continuation in
            waiting[make] = continuation
        }
    }

    /// Answers one outstanding call. Returns false if nothing is waiting on it.
    @discardableResult
    func answer(make: String, with models: [String]) -> Bool {
        guard let continuation = waiting.removeValue(forKey: make) else { return false }
        continuation.resume(returning: models)
        return true
    }

    func callCount() -> Int { calls.count }

    /// Waits until `make` has an outstanding call, so a test never answers a
    /// request that has not been made yet.
    func waitForCall(make: String, timeout: TimeInterval = 5) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if waiting[make] != nil { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return waiting[make] != nil
    }
}

/// Answers with a canned list of configurations rather than asking a
/// government API what a 2010 Jeep was sold with.
struct StubConfigurationOptionProvider: VehicleConfigurationOptionProvider {
    var displayName = "Stub configuration provider"
    var contactedHost = "example.invalid"
    /// Named `answer` rather than `options` so the method body below cannot
    /// be read as referring to the method itself.
    var answer: [VehicleConfigurationOption] = []
    var error: ProviderError?
    /// Set to hold the answer until the gate is opened, so a test can move on
    /// to a different vehicle while the first request is still in flight.
    var gate: AsyncGate?

    func options(modelYear: Int, make: String, model: String) async throws -> [VehicleConfigurationOption] {
        if let gate { await gate.wait() }
        if let error { throw error }
        return answer
    }
}

/// A one-shot gate a test can hold a provider behind.
actor AsyncGate {
    private var isOpen = false
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    func wait() async {
        if isOpen { return }
        let token = UUID()
        await withCheckedContinuation { continuation in
            waiters[token] = continuation
        }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters = [:]
        for (_, continuation) in pending { continuation.resume() }
    }
}
