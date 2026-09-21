import Foundation
import OdomindCore

/// What a VIN decode gave back, and what it did not.
///
/// vPIC frequently returns blanks for trim, engine model and transmission. The
/// result records which fields came back empty so the confirmation screen can
/// ask about exactly those rather than presenting a form full of guesses.
struct VehicleDecodeResult: Sendable, Hashable {
    var identity: VehicleIdentity
    var configuration: VehicleConfiguration
    /// Messages the provider itself reported, e.g. a bad check digit.
    var providerMessages: [String]
    /// Human-readable names of fields the provider left blank.
    var missingFields: [String]
    /// A corrected VIN the provider suggested, when it thinks one digit is off.
    var suggestedVIN: String?
    /// Every non-empty field, for the "what the decoder said" disclosure.
    var reportedFields: [DecodedField]

    var isPartial: Bool { !missingFields.isEmpty }

    struct DecodedField: Sendable, Hashable, Identifiable {
        var id: String { name }
        var name: String
        var value: String
    }
}

enum ProviderError: Error, LocalizedError, Equatable {
    case notConnected
    case timedOut
    case serviceUnavailable(statusCode: Int)
    case unreadableResponse(String)
    case vinRejected(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Odomind could not reach the vehicle lookup service. You can still add this vehicle by hand."
        case .timedOut:
            return "The vehicle lookup service did not answer in time. You can try again or add this vehicle by hand."
        case .serviceUnavailable(let statusCode):
            return "The vehicle lookup service returned an error (\(statusCode)). You can add this vehicle by hand."
        case .unreadableResponse:
            return "The vehicle lookup service returned something Odomind could not read. You can add this vehicle by hand."
        case .vinRejected(let reason):
            return reason
        case .cancelled:
            return "Lookup cancelled."
        }
    }

    /// Every provider failure is recoverable by hand, which is why the app never
    /// blocks vehicle creation on one.
    var suggestsManualEntry: Bool {
        switch self {
        case .cancelled: return false
        default: return true
        }
    }
}

/// Identification only. A decoder tells you what the vehicle is, never what
/// fluid it takes, which is why this protocol cannot return a specification.
protocol VehicleIdentificationProvider: Sendable {
    /// Human-readable name shown in the app's data-sources screen.
    var displayName: String { get }
    /// The host the app contacts, disclosed before the first lookup.
    var contactedHost: String { get }

    func decode(vin: String, modelYear: Int?) async throws -> VehicleDecodeResult
    func models(make: String, modelYear: Int) async throws -> [String]

    /// Every model a make has built, with no year supplied.
    ///
    /// This is what lets somebody type "Wrangler" and get somewhere. Build 2
    /// had no such call, which is why it demanded a year before it would ask
    /// the provider anything — a requirement that turned out to be
    /// unnecessary rather than unavoidable: vPIC's GetModelsForMake answers
    /// without one, and a live probe returned 24 Jeep models that way.
    func models(make: String) async throws -> [String]
}

extension VehicleIdentificationProvider {
    /// Providers written before the yearless call existed still compile; they
    /// simply offer nothing rather than breaking the search.
    func models(make: String) async throws -> [String] { [] }
}
