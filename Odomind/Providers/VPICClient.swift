import Foundation
import OdomindCore

/// NHTSA Product Information Catalog and Vehicle Listing (vPIC).
///
/// Used for identification only. vPIC carries no maintenance schedules, no
/// fluid specifications and no fitment data, and its `GetParts` endpoint is a
/// list of manufacturer regulatory submissions rather than a replacement-parts
/// catalog — so this client never asks it for any of those.
///
/// The VIN is the only identifying value Odomind ever sends anywhere. It is put
/// in the URL path because that is the API's shape; it is never written to a
/// log, an analytics event or a crash report.
struct VPICClient: VehicleIdentificationProvider {
    static let defaultBaseURL = URL(string: "https://vpic.nhtsa.dot.gov/api/vehicles/")!

    let baseURL: URL
    let session: URLSession
    /// Total attempts, including the first. Bounded so a struggling service
    /// cannot hold the setup flow open indefinitely.
    let maximumAttempts: Int

    var displayName: String { "NHTSA vPIC" }
    var contactedHost: String { baseURL.host ?? "vpic.nhtsa.dot.gov" }

    init(
        baseURL: URL = VPICClient.defaultBaseURL,
        session: URLSession = VPICClient.makeSession(),
        maximumAttempts: Int = 3
    ) {
        self.baseURL = baseURL
        self.session = session
        self.maximumAttempts = maximumAttempts
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .useProtocolCachePolicy
        // A small private cache. Decoding the same VIN twice during setup should
        // not mean two round trips, and it keeps the response out of the shared
        // system cache.
        configuration.urlCache = URLCache(memoryCapacity: 2 * 1024 * 1024, diskCapacity: 8 * 1024 * 1024)
        configuration.httpAdditionalHeaders = ["Accept": "application/json"]
        return URLSession(configuration: configuration)
    }

    // MARK: - Decoding

    func decode(vin: String, modelYear: Int?) async throws -> VehicleDecodeResult {
        let normalized = VIN.normalize(vin)
        let blocking = VIN.problems(in: normalized).filter(\.isBlocking)
        if let first = blocking.first {
            throw ProviderError.vinRejected(first.message)
        }

        var components = URLComponents(
            url: baseURL.appendingPathComponent("decodevinvalues").appendingPathComponent(normalized),
            resolvingAgainstBaseURL: false
        )
        var query = [URLQueryItem(name: "format", value: "json")]
        if let modelYear {
            query.append(URLQueryItem(name: "modelyear", value: String(modelYear)))
        }
        components?.queryItems = query

        guard let url = components?.url else {
            throw ProviderError.unreadableResponse("Could not build the lookup URL.")
        }

        let data = try await fetch(url)
        let envelope: VPICEnvelope
        do {
            envelope = try JSONDecoder().decode(VPICEnvelope.self, from: data)
        } catch {
            throw ProviderError.unreadableResponse("Unexpected response shape.")
        }
        guard let record = envelope.results.first else {
            throw ProviderError.unreadableResponse("The service returned no results.")
        }

        return VPICMapper.map(record: record, requestedVIN: normalized, requestedYear: modelYear)
    }

    func models(make: String, modelYear: Int) async throws -> [String] {
        let trimmedMake = make.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMake.isEmpty else { return [] }

        var components = URLComponents(
            url: baseURL
                .appendingPathComponent("getmodelsformakeyear")
                .appendingPathComponent("make")
                .appendingPathComponent(trimmedMake)
                .appendingPathComponent("modelyear")
                .appendingPathComponent(String(modelYear)),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "format", value: "json")]

        guard let url = components?.url else { return [] }
        let data = try await fetch(url)
        guard let envelope = try? JSONDecoder().decode(VPICEnvelope.self, from: data) else {
            throw ProviderError.unreadableResponse("Unexpected response shape.")
        }
        let names = envelope.results.compactMap { $0["Model_Name"]?.stringValue }
        return Array(Set(names)).sorted()
    }

    /// Every model for a make, no year. vPIC answers this directly.
    func models(make: String) async throws -> [String] {
        let trimmedMake = make.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMake.isEmpty else { return [] }

        var components = URLComponents(
            url: baseURL
                .appendingPathComponent("getmodelsformake")
                .appendingPathComponent(trimmedMake),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "format", value: "json")]

        guard let url = components?.url else { return [] }
        let data = try await fetch(url)
        guard let envelope = try? JSONDecoder().decode(VPICEnvelope.self, from: data) else {
            throw ProviderError.unreadableResponse("Unexpected response shape.")
        }
        let names = envelope.results.compactMap { $0["Model_Name"]?.stringValue }
        return Array(Set(names)).sorted()
    }

    // MARK: - Transport

    /// One request with bounded retry.
    ///
    /// Retries only what is worth retrying: a timeout, a dropped connection or a
    /// 5xx. A 404 or a malformed VIN is answered immediately, because trying
    /// again will not change it.
    private func fetch(_ url: URL) async throws -> Data {
        var attempt = 1
        var lastError: ProviderError = .timedOut

        while attempt <= maximumAttempts {
            if Task.isCancelled { throw ProviderError.cancelled }
            do {
                let (data, response) = try await session.data(from: url)
                guard let http = response as? HTTPURLResponse else {
                    return data
                }
                switch http.statusCode {
                case 200..<300:
                    return data
                case 500..<600:
                    lastError = .serviceUnavailable(statusCode: http.statusCode)
                default:
                    throw ProviderError.serviceUnavailable(statusCode: http.statusCode)
                }
            } catch let error as ProviderError {
                throw error
            } catch let error as URLError {
                switch error.code {
                case .cancelled:
                    throw ProviderError.cancelled
                case .notConnectedToInternet, .dataNotAllowed, .cannotFindHost, .cannotConnectToHost:
                    throw ProviderError.notConnected
                case .timedOut, .networkConnectionLost:
                    lastError = .timedOut
                default:
                    lastError = .unreadableResponse(error.localizedDescription)
                }
            } catch {
                lastError = .unreadableResponse(String(describing: error))
            }

            if attempt < maximumAttempts {
                // 0.5s, then 1.0s. Short enough that a person waiting through
                // setup does not give up, long enough to clear a blip.
                let backoff = UInt64(500_000_000) << UInt64(attempt - 1)
                do {
                    try await Task.sleep(nanoseconds: backoff)
                } catch {
                    throw ProviderError.cancelled
                }
            }
            attempt += 1
        }

        throw lastError
    }
}

/// vPIC wraps every response in the same envelope.
struct VPICEnvelope: Decodable {
    let count: Int?
    let message: String?
    let results: [[String: VPICField]]

    private enum CodingKeys: String, CodingKey {
        case count = "Count"
        case message = "Message"
        case results = "Results"
    }
}

/// vPIC returns a mix of strings, numbers and nulls in the same object, so
/// every field is decoded through this rather than assumed to be a string.
enum VPICField: Decodable, Hashable {
    case text(String)
    case number(Double)
    case empty

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .empty
            return
        }
        if let value = try? container.decode(String.self) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            self = trimmed.isEmpty ? .empty : .text(trimmed)
            return
        }
        if let value = try? container.decode(Double.self) {
            self = .number(value)
            return
        }
        if let value = try? container.decode(Bool.self) {
            self = .text(value ? "true" : "false")
            return
        }
        self = .empty
    }

    var stringValue: String? {
        switch self {
        case .text(let value): return value
        case .number(let value):
            if value == value.rounded() && abs(value) < 1e15 { return String(Int(value)) }
            return String(value)
        case .empty: return nil
        }
    }

    var intValue: Int? {
        switch self {
        case .number(let value): return Int(value)
        case .text(let value): return Int(value)
        case .empty: return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case .number(let value): return value
        case .text(let value): return Double(value)
        case .empty: return nil
        }
    }
}
