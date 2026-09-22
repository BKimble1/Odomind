import Foundation
import OdomindCore

/// A studio photograph of a specific year, make and model — the kind a
/// manufacturer or dealer publishes: the car cut out, lit, on nothing.
///
/// **This is the one piece of Build 4 that money buys and nothing else does.**
///
/// Manufacturer press photography is copyrighted. It is published for
/// editorial use, not for redistribution inside a product, and "a picture for
/// every car" means complete coverage of every year, make, model and trim an
/// owner might enter — which no free source has. The providers that do have it
/// license it:
///
/// - **Evox Images** — the widest US catalogue of studio vehicle photography,
///   angles and colours per trim. Per-image or subscription; **quote required**.
/// - **Chrome Data (J.D. Power)** — vehicle description data with images
///   alongside it, which would also help the specification gap; **quote
///   required**.
/// - **IMAGIN.studio** — renders rather than photographs, addressed by make,
///   model and angle over a URL, which is the least work to integrate;
///   **quote required**.
///
/// No vendor has been contacted and no agreement has been accepted. Until one
/// is in place this returns nothing and the ladder below it takes over, so
/// every car still gets a picture — Odomind's own drawing, presented the same
/// way, rather than an empty frame.
///
/// When a licence does exist, the only change is a type conforming to this
/// protocol and a key kept out of the repository and out of the client.
protocol LicensedVehicleImageProvider: Sendable {
    var displayName: String { get }
    /// The studio image for this vehicle, or nil when the provider has none.
    func studioImageURL(for identity: VehicleIdentity, paint: VehiclePaintColor) async -> URL?
}

/// The provider in the shipping build: there is no licence, so there is no
/// image. Deliberately not a stub that returns a placeholder URL — a broken
/// image is worse than a drawing, and a fake one is worse than both.
struct UnlicensedVehicleImageProvider: LicensedVehicleImageProvider {
    var displayName: String { "None — no image licence" }

    func studioImageURL(for identity: VehicleIdentity, paint: VehiclePaintColor) async -> URL? {
        nil
    }
}
