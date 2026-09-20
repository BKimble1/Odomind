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
