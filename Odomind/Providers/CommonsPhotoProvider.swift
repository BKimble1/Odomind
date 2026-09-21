import Foundation
import OdomindCore

/// Finds a real photograph of a vehicle on Wikimedia Commons.
///
/// Chosen because it is the one source of real vehicle photography that is
/// free, has a documented reuse policy, and states a licence and an author
/// alongside every file — which is what makes showing the picture lawful
/// rather than merely possible. A live probe returned eight licensed
/// candidates each for a 2010 Wrangler and a Camry XV40, so the coverage is
/// real for ordinary vehicles; it is uneven for unusual ones, which is why a
/// quiet fallback stays in the app.
///
/// What this deliberately does not do: take the first image-search result.
/// Commons is full of engine bays, dashboards, badges and wrecks, and a query
/// for a Wrangler will return several. Candidates are scored on the words in
/// their own title before any of them is offered.
protocol VehiclePhotoProvider: Sendable {
    var displayName: String { get }
    var contactedHost: String { get }

    func photo(for request: VehiclePhotoRequest) async throws -> VehiclePhoto?
}

/// What to look for, and how closely it has to match to count.
struct VehiclePhotoRequest: Hashable, Sendable {
    var modelYear: Int?
    var make: String
    var model: String
    var bodyClass: String?
    /// Words that must not appear in a candidate's title, because they name a
    /// different variant of the same model. A two-door photo is not a photo of
    /// a four-door car, and the brief is explicit that Odomind must not imply
    /// it is.
    var excludedWords: [String] = []

    var displayName: String {
        [modelYear.map(String.init), make, model].compactMap { $0 }.joined(separator: " ")
    }
}

/// Commons photographs, via the MediaWiki API.
struct CommonsPhotoProvider: VehiclePhotoProvider {
    var displayName: String { "Wikimedia Commons" }
    var contactedHost: String { "commons.wikimedia.org" }

    private let session: URLSession
    private let now: @Sendable () -> Date

    init(session: URLSession = .shared, now: @escaping @Sendable () -> Date = { Date() }) {
        self.session = session
        self.now = now
    }

    /// Subject words that mean the picture is of a part of a car rather than
    /// of a car. Filtered out before ranking, because a well-titled photo of a
    /// Wrangler's engine is still not a photo of a Wrangler.
    private static let notAWholeVehicle = [
        "engine", "interior", "dashboard", "dash", "badge", "logo", "emblem",
        "wheel", "tire", "tyre", "seat", "trunk", "boot", "bumper", "headlight",
        "taillight", "crash", "wreck", "accident", "fire", "rusty", "junkyard",
        "scrap", "diagram", "drawing", "blueprint", "assembly", "factory",
        "museum sign", "brochure", "advertisement", "poster", "toy", "model car",
    ]

    func photo(for request: VehiclePhotoRequest) async throws -> VehiclePhoto? {
        // Most specific first; stop at the first level that answers, so an
        // exact-year photo is never passed over for a generation one.
        var attempts: [(query: String, level: PhotoMatchLevel)] = []
        if let year = request.modelYear {
            attempts.append(("\(year) \(request.make) \(request.model)", .exactModelYear))
        }
        attempts.append(("\(request.make) \(request.model)", .generation))

        for attempt in attempts {
            if let found = try await search(attempt.query, level: attempt.level, request: request) {
                return found
            }
        }
        return nil
    }

    private func search(_ query: String, level: PhotoMatchLevel, request: VehiclePhotoRequest) async throws -> VehiclePhoto? {
        var components = URLComponents(string: "https://commons.wikimedia.org/w/api.php")
        components?.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2"),
            URLQueryItem(name: "generator", value: "search"),
            // Namespace 6 is File:, so this never returns article text.
            URLQueryItem(name: "gsrnamespace", value: "6"),
            URLQueryItem(name: "gsrlimit", value: "20"),
            URLQueryItem(name: "gsrsearch", value: query),
            URLQueryItem(name: "prop", value: "imageinfo"),
            URLQueryItem(name: "iiprop", value: "url|extmetadata|mime|size"),
            // A display-sized rendering rather than the original, which can be
            // twenty megapixels of something nobody is going to zoom into.
            URLQueryItem(name: "iiurlwidth", value: "1024"),
        ]
        guard let url = components?.url else { return nil }

        var urlRequest = URLRequest(url: url)
        urlRequest.timeoutInterval = 20
        // Commons asks API clients to identify themselves.
        urlRequest.setValue("Odomind/1.2 (https://github.com/BKimble1/Odomind)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ProviderError.serviceUnavailable(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let payload: CommonsResponse
        do {
            payload = try JSONDecoder().decode(CommonsResponse.self, from: data)
        } catch {
            throw ProviderError.unreadableResponse("Unexpected response shape.")
        }

        let ranked = payload.query?.pages?
            .compactMap { page -> (page: CommonsResponse.Page, info: CommonsResponse.ImageInfo, score: Int)? in
                guard let info = page.imageinfo?.first else { return nil }
                guard info.mime?.hasPrefix("image/") == true else { return nil }
                guard let score = score(title: page.title, info: info, request: request) else { return nil }
                return (page, info, score)
            }
            .sorted { $0.score > $1.score }

        guard let best = ranked?.first else { return nil }

        let meta = best.info.extmetadata
        let licence = meta?["LicenseShortName"]?.value ?? ""
        let artist = Self.stripMarkup(meta?["Artist"]?.value ?? "")
        let licenceURL = (meta?["LicenseUrl"]?.value).flatMap(URL.init(string:))

        guard let imageURL = URL(string: best.info.thumburl ?? best.info.url ?? "") else { return nil }

        let photo = VehiclePhoto(
            sourceIdentifier: "commons:\(best.page.title)",
            providerName: displayName,
            imageURL: imageURL,
            pageURL: (best.info.descriptionurl).flatMap(URL.init(string:)),
            licenceName: licence,
            licenceURL: licenceURL,
            attribution: artist,
            matchLevel: level,
            matchedQuery: query,
            retrievedOn: now(),
            pixelWidth: best.info.thumbwidth ?? best.info.width,
            pixelHeight: best.info.thumbheight ?? best.info.height
        )

        // The last gate: a record Odomind may not lawfully display is not a
        // record it falls back to showing anyway.
        return photo.isDisplayable ? photo : nil
    }

    /// How well a file's own title describes a whole vehicle of the right
    /// kind. `nil` disqualifies it.
    private func score(title: String, info: CommonsResponse.ImageInfo, request: VehiclePhotoRequest) -> Int? {
        let tokens = Set(VehicleTextMatch.tokens(title))
        guard !tokens.isEmpty else { return nil }

        for word in Self.notAWholeVehicle where tokens.contains(VehicleTextMatch.normalise(word)) {
            return nil
        }
        for word in request.excludedWords where tokens.contains(VehicleTextMatch.normalise(word)) {
            return nil
        }

        // A landscape image is far more likely to be the whole car.
        let width = info.thumbwidth ?? info.width ?? 0
        let height = info.thumbheight ?? info.height ?? 0
        guard width == 0 || height == 0 || width >= height else { return nil }

        var score = 0
        for token in VehicleTextMatch.tokens(request.make) where tokens.contains(token) { score += 4 }
        for token in VehicleTextMatch.tokens(request.model) where tokens.contains(token) { score += 6 }
        if let year = request.modelYear {
            // Commons titles often abbreviate: "'10 Jeep Wrangler".
            let full = String(year)
            let short = String(full.suffix(2))
            if tokens.contains(full) { score += 5 } else if tokens.contains(short) { score += 2 }
        }
        // The make and the model both have to appear somewhere, or this is a
        // photograph of something else that happened to match a word.
        let hasMake = VehicleTextMatch.tokens(request.make).contains { tokens.contains($0) }
        let hasModel = VehicleTextMatch.tokens(request.model).contains { tokens.contains($0) }
        guard hasMake, hasModel else { return nil }

        return score
    }

    /// Commons returns HTML in `extmetadata`. The author's name is wanted, the
    /// anchor tag is not.
    static func stripMarkup(_ html: String) -> String {
        let withoutTags = html.replacingOccurrences(
            of: "<[^>]+>", with: "", options: .regularExpression
        )
        return withoutTags
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Wire format

private struct CommonsResponse: Decodable {
    struct MetadataValue: Decodable {
        var value: String

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            // `value` is a string most of the time and a number occasionally.
            if let nested = try? container.decode([String: AnyDecodable].self),
               let raw = nested["value"] {
                value = raw.stringValue
            } else {
                value = ""
            }
        }
    }

    struct ImageInfo: Decodable {
        var url: String?
        var descriptionurl: String?
        var thumburl: String?
        var thumbwidth: Int?
        var thumbheight: Int?
        var width: Int?
        var height: Int?
        var mime: String?
        var extmetadata: [String: MetadataValue]?
    }

    struct Page: Decodable {
        var title: String
        var imageinfo: [ImageInfo]?
    }

    struct Query: Decodable {
        var pages: [Page]?
    }

    var query: Query?
}

/// Just enough to read a heterogeneous `value` field without dragging in a
/// whole dynamic-JSON dependency.
private struct AnyDecodable: Decodable {
    let stringValue: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            stringValue = text
        } else if let number = try? container.decode(Int.self) {
            stringValue = String(number)
        } else if let flag = try? container.decode(Bool.self) {
            stringValue = String(flag)
        } else {
            stringValue = ""
        }
    }
}
