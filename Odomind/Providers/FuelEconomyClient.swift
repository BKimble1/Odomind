import Foundation
import OdomindCore

/// The configurations a vehicle was actually sold in.
///
/// Odomind asks a provider rather than a picker. See
/// `VehicleConfigurationOption` for why.
protocol VehicleConfigurationOptionProvider: Sendable {
    var displayName: String { get }
    var contactedHost: String { get }
    func options(modelYear: Int, make: String, model: String) async throws -> [VehicleConfigurationOption]
}

/// fueleconomy.gov — the US Department of Energy and EPA's fuel economy data.
///
/// **Why this one.** It is a documented public REST API from a US government
/// agency, its data is a work of the United States Government and therefore in
/// the public domain, and it answers the exact question Build 3's setup step
/// needs: which engine, transmission and drivetrain combinations were sold for
/// this year, make and model. Odomind calls it once per vehicle the owner is
/// adding. It is not scraped, not harvested in bulk, and no key is needed — so
/// nothing secret has to travel in the client.
///
/// **What it is not.** It carries no maintenance schedules, no fluid
/// capacities and no part numbers. Nothing here pretends otherwise: the
/// options it returns fill in configuration, and configuration alone.
///
/// **What Odomind sends.** A year, a make and a model. No VIN, no mileage, no
/// identifier of any kind.
struct FuelEconomyClient: VehicleConfigurationOptionProvider {
    static let defaultBaseURL = URL(string: "https://www.fueleconomy.gov/ws/rest/")!
    /// The key this service's ids are stored under on a vehicle. A constant,
    /// not the display name: renaming what the owner reads must not orphan
    /// every identifier already saved.
    static let providerKey = "fueleconomy.gov"

    let baseURL: URL
    let session: URLSession
    let clock: OdomindClock
    /// How many configurations to describe in full. The menu is cheap; each
    /// detail is another round trip, and a vehicle sold in thirty variants
    /// does not need thirty requests to make the setup step useful.
    let maximumDetailed: Int

    var displayName: String { "fueleconomy.gov (US DOE/EPA)" }
    var contactedHost: String { baseURL.host ?? "www.fueleconomy.gov" }

    init(
        baseURL: URL = FuelEconomyClient.defaultBaseURL,
        session: URLSession = FuelEconomyClient.makeSession(),
        clock: OdomindClock = SystemClock(),
        maximumDetailed: Int = 8
    ) {
        self.baseURL = baseURL
        self.session = session
        self.clock = clock
        self.maximumDetailed = maximumDetailed
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .useProtocolCachePolicy
        configuration.urlCache = URLCache(memoryCapacity: 1024 * 1024, diskCapacity: 4 * 1024 * 1024)
        // The service answers XML unless asked otherwise, and the ask is a
        // header rather than a query parameter.
        configuration.httpAdditionalHeaders = ["Accept": "application/json"]
        return URLSession(configuration: configuration)
    }

    // MARK: - Options

    func options(modelYear: Int, make: String, model: String) async throws -> [VehicleConfigurationOption] {
        // What *this* service calls the model, first.
        //
        // vPIC says "Wrangler"; fueleconomy.gov says "Wrangler 4WD" and
        // "Wrangler 2WD". Asking it about a name it does not use returns an
        // empty menu, which reads as "no coverage" when the real problem is
        // two vocabularies for the same car. A live probe caught this: the
        // first version of this client would have found nothing, for every
        // vehicle whose name is not spelled identically in both services.
        let names = try await modelNames(modelYear: modelYear, make: make, model: model)
        guard !names.isEmpty else { return [] }

        var options: [VehicleConfigurationOption] = []
        // More than one name means the service splits the model — usually by
        // drivetrain — so both sets are offered and the owner picks, rather
        // than Odomind choosing one of their cars for them.
        let namesAreAmbiguous = names.count > 1

        for name in names {
            if Task.isCancelled { throw ProviderError.cancelled }
            guard options.count < maximumDetailed else { break }
            let items = try await menu(modelYear: modelYear, make: make, model: name)

            for item in items {
                if Task.isCancelled { throw ProviderError.cancelled }
                guard options.count < maximumDetailed else { break }
                let detail = try? await detail(id: item.value)
                options.append(
                    VehicleConfigurationOption(
                        id: item.value,
                        providerName: displayName,
                        providerKey: Self.providerKey,
                        providerURL: URL(string: "https://www.fueleconomy.gov/feg/Find.do?action=sbs&id=\(item.value)"),
                        // The provider's own words. An option whose detail
                        // call failed still shows this, which is the part the
                        // owner reads and recognises. The model name is added
                        // only when it is the thing telling two options
                        // apart.
                        label: namesAreAmbiguous ? "\(name) — \(item.text)" : item.text,
                        engineDisplacementLiters: detail?.displ.flatMap(Double.init),
                        cylinders: detail?.cylinders.flatMap(Int.init),
                        transmissionDescription: detail?.trany,
                        driveDescription: detail?.drive,
                        fuelDescription: detail?.fuelType,
                        vehicleClass: detail?.vClass,
                        engineDescription: detail?.engineDescription,
                        retrievedOn: clock.now
                    )
                )
            }
        }
        return options
    }

    /// The names this service uses for a model somebody named differently.
    ///
    /// An exact name wins outright. Otherwise every name that begins with what
    /// was asked for is a candidate — "Wrangler" finds both "Wrangler 2WD" and
    /// "Wrangler 4WD", and both are worth offering.
    ///
    /// **Shortest first, and that is not arbitrary.** A live probe asked this
    /// service about a 2018 F-150 and got twenty names back: "F150 Pickup
    /// 2WD" and "F150 Pickup 4WD" alongside "F150 2.7L 2WD GVWR>6649 LBS",
    /// "F150 2WD FFV BASE PAYLOAD LT TIRE" and sixteen more. Taking the first
    /// few alphabetically handed the owner the payload and gross-weight
    /// variants and hid the two ordinary trucks. The plain name is the short
    /// one, every time, because the extra words are qualifiers.
    ///
    /// Capped at four, because a model spelled twenty ways is a reason to ask
    /// the owner — which "None of these is mine" does — not to make sixty
    /// requests.
    private func modelNames(modelYear: Int, make: String, model: String) async throws -> [String] {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("vehicle/menu/model"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "year", value: String(modelYear)),
            URLQueryItem(name: "make", value: make),
        ]
        guard let url = components?.url else {
            throw ProviderError.unreadableResponse("Could not build the model URL.")
        }

        let data = try await fetch(url)
        guard let menu = try? JSONDecoder().decode(MenuEnvelope.self, from: data) else {
            throw ProviderError.unreadableResponse("Unexpected model menu shape.")
        }
        let names = menu.items.map(\.value)
        guard !names.isEmpty else { return [] }

        let wanted = VehicleTextMatch.key(model)
        guard !wanted.isEmpty else { return [] }

        if let exact = names.first(where: { VehicleTextMatch.key($0) == wanted }) {
            return [exact]
        }
        let matching = names.filter { VehicleTextMatch.key($0).hasPrefix(wanted) }
        let plainestFirst = matching.sorted { left, right in
            if left.count != right.count { return left.count < right.count }
            return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
        }
        return Array(plainestFirst.prefix(4))
    }

    /// The configuration menu for one of this service's own model names.
    private func menu(modelYear: Int, make: String, model: String) async throws -> [MenuEnvelope.Item] {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("vehicle/menu/options"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "year", value: String(modelYear)),
            URLQueryItem(name: "make", value: make),
            URLQueryItem(name: "model", value: model),
        ]
        guard let url = components?.url else {
            throw ProviderError.unreadableResponse("Could not build the options URL.")
        }
        let data = try await fetch(url)
        guard let menu = try? JSONDecoder().decode(MenuEnvelope.self, from: data) else {
            throw ProviderError.unreadableResponse("Unexpected response shape.")
        }
        return menu.items
    }

    private func detail(id: String) async throws -> VehicleDetail {
        let url = baseURL.appendingPathComponent("vehicle").appendingPathComponent(id)
        let data = try await fetch(url)
        do {
            return try JSONDecoder().decode(VehicleDetail.self, from: data)
        } catch {
            throw ProviderError.unreadableResponse("Unexpected detail shape.")
        }
    }

    // MARK: - Transport

    private func fetch(_ url: URL) async throws -> Data {
        if Task.isCancelled { throw ProviderError.cancelled }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse else { return data }
            guard (200..<300).contains(http.statusCode) else {
                throw ProviderError.serviceUnavailable(statusCode: http.statusCode)
            }
            return data
        } catch let error as ProviderError {
            throw error
        } catch let error as URLError {
            switch error.code {
            case .cancelled: throw ProviderError.cancelled
            case .notConnectedToInternet, .dataNotAllowed, .cannotFindHost, .cannotConnectToHost:
                throw ProviderError.notConnected
            case .timedOut, .networkConnectionLost: throw ProviderError.timedOut
            default: throw ProviderError.unreadableResponse(error.localizedDescription)
            }
        } catch {
            throw ProviderError.unreadableResponse(String(describing: error))
        }
    }
}

// MARK: - Wire shapes

/// The menu endpoint answers `{"menuItem": [...]}` for several options and
/// `{"menuItem": {...}}` for exactly one. Both are decoded here rather than
/// letting the single-variant case read as an empty list — which would make
/// the app quietly fall back to generic pickers for every vehicle sold in one
/// configuration.
struct MenuEnvelope: Decodable {
    struct Item: Decodable {
        var text: String
        var value: String
    }

    var items: [Item]

    private enum CodingKeys: String, CodingKey {
        case menuItem
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let many = try? container.decode([Item].self, forKey: .menuItem) {
            items = many
        } else if let one = try? container.decode(Item.self, forKey: .menuItem) {
            items = [one]
        } else {
            items = []
        }
    }
}

/// One configuration's facts. Every field is optional and every numeric one
/// arrives as a string, which is the service's own shape rather than a
/// convenience taken here.
private struct VehicleDetail: Decodable {
    var displ: String?
    var cylinders: String?
    var trany: String?
    var drive: String?
    var fuelType: String?
    var vClass: String?
    var engineDescription: String?

    private enum CodingKeys: String, CodingKey {
        case displ, cylinders, trany, drive, fuelType
        case vClass = "VClass"
        case engineDescription = "eng_dscr"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displ = Self.string(container, .displ)
        cylinders = Self.string(container, .cylinders)
        trany = try? container.decodeIfPresent(String.self, forKey: .trany)
        drive = try? container.decodeIfPresent(String.self, forKey: .drive)
        fuelType = try? container.decodeIfPresent(String.self, forKey: .fuelType)
        vClass = try? container.decodeIfPresent(String.self, forKey: .vClass)
        engineDescription = try? container.decodeIfPresent(String.self, forKey: .engineDescription)
    }

    /// Numbers come back as strings here, but a JSON producer that changes its
    /// mind about that should not take the whole decode down with it.
    private static func string(
        _ container: KeyedDecodingContainer<CodingKeys>,
        _ key: CodingKeys
    ) -> String? {
        if let text = try? container.decodeIfPresent(String.self, forKey: key) { return text }
        if let number = try? container.decodeIfPresent(Double.self, forKey: key) {
            return number == number.rounded() ? String(Int(number)) : String(number)
        }
        return nil
    }
}
