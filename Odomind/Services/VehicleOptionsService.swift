import Foundation
import Observation
import OdomindCore

/// Fetches the configurations a vehicle was actually sold in, for the setup
/// step to offer instead of a picker containing every powertrain ever built.
///
/// Built to the same rule as the photo service and the search, because they
/// all have the same failure: **a late answer must not land on a different
/// car.** Every request carries a generation; an answer whose generation is no
/// longer current is dropped rather than shown. Somebody who types one vehicle,
/// changes their mind and types another must not be offered the first one's
/// engines.
///
/// And the same rule as everything else in Odomind about absence: when the
/// provider has nothing, the app says so and falls back to asking, rather than
/// presenting a guess as a provider-backed fact.
@MainActor
@Observable
final class VehicleOptionsService {

    enum Status: Equatable {
        case idle
        case looking
        case options([VehicleConfigurationOption])
        /// Asked, and there is nothing to offer. The generic questions belong
        /// here, along with a line saying why they are being asked.
        case none(String)

        var options: [VehicleConfigurationOption] {
            if case .options(let found) = self { return found }
            return []
        }
    }

    private(set) var status: Status = .idle
    /// The option the owner picked, if any. Kept here rather than in the view
    /// so leaving and returning to the step does not lose it.
    var selectedOptionID: String?

    private let provider: VehicleConfigurationOptionProvider
    private let enabled: Bool
    private var generation = 0
    private var task: Task<Void, Never>?
    /// What the current status is for, so an unchanged vehicle is not asked
    /// about twice.
    private var currentKey: String?

    var providerName: String { provider.displayName }
    var providerHost: String { provider.contactedHost }

    init(provider: VehicleConfigurationOptionProvider? = nil, enabled: Bool = true) {
        self.provider = provider ?? FuelEconomyClient()
        self.enabled = enabled
    }

    /// A fingerprint of the three things the request is made from.
    nonisolated static func key(modelYear: Int?, make: String, model: String) -> String? {
        guard let modelYear else { return nil }
        let make = VehicleTextMatch.normalise(make)
        let model = VehicleTextMatch.normalise(model)
        guard !make.isEmpty, !model.isEmpty else { return nil }
        return "\(modelYear)|\(make)|\(model)"
    }

    func resolve(modelYear: Int?, make: String, model: String, force: Bool = false) {
        guard let key = Self.key(modelYear: modelYear, make: make, model: model) else {
            cancel()
            status = .none(
                "Odomind needs a year before it can look up which engines this was sold with. "
                    + "Go back a step to pick one."
            )
            currentKey = nil
            return
        }

        if !force, key == currentKey, status != .idle { return }

        cancel()
        currentKey = key
        selectedOptionID = nil

        guard enabled, let modelYear else {
            status = .none("Odomind could not check which configurations this was sold in.")
            return
        }

        status = .looking
        generation += 1
        let mine = generation
        let provider = self.provider

        task = Task { [weak self] in
            let found = try? await provider.options(modelYear: modelYear, make: make, model: model)
            guard let self else { return }
            await self.finish(found, generation: mine)
        }
    }

    func cancel() {
        generation += 1
        task?.cancel()
        task = nil
    }

    func option(id: String?) -> VehicleConfigurationOption? {
        guard let id else { return nil }
        return status.options.first { $0.id == id }
    }

    private func finish(_ found: [VehicleConfigurationOption]?, generation mine: Int) async {
        // The guard that stops one car's engines being offered for another.
        guard generation == mine else { return }
        task = nil

        guard let found, !found.isEmpty else {
            status = .none("Odomind could not find a published list of configurations for this vehicle.")
            return
        }
        status = .options(found)

        // One configuration means there is nothing to choose between, so it is
        // applied rather than presented as a decision.
        if found.count == 1 { selectedOptionID = found[0].id }
    }
}
