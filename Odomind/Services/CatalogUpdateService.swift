import Foundation
import CryptoKit
import OdomindCore

/// What the remote manifest says is available.
struct CatalogManifest: Decodable, Hashable, Sendable {
    var catalogVersion: String
    var schemaVersion: Int
    var publishedOn: Date
    /// Where the catalog itself is. Must be HTTPS and must be on the pinned
    /// host; anything else is refused before a byte is fetched.
    var url: URL
    /// Lowercase hex SHA-256 of the catalog file.
    var sha256: String
    var byteCount: Int
    /// A line for the owner describing what changed.
    var summary: String?
}

enum CatalogUpdateResult: Equatable {
    case upToDate(version: String)
    case installed(version: String)
    case rejected(String)
    case unreachable(String)
}

/// Where an installed catalog lives on disk, and the rules for trusting one.
///
/// Installation is atomic: the file is written beside the live one and then
/// swapped in, so a process that dies mid-write leaves the previous catalog
/// intact rather than half of a new one. There is no "partially updated"
/// state to recover from because one never exists.
struct CatalogUpdateStore {
    let directory: URL

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = (try? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            )) ?? FileManager.default.temporaryDirectory
            self.directory = base.appendingPathComponent("Catalog", isDirectory: true)
        }
    }

    var installedURL: URL { directory.appendingPathComponent("odomind-catalog.json") }

    /// Reads the installed catalog, if there is one worth using.
    ///
    /// Four gates, all of which must pass: it parses, its schema version is
    /// one this build understands, it validates as strictly as CI validates
    /// the bundled one, and it is not older than the bundled copy. A downgrade
    /// is refused because a stale file on disk must not undo a fix that
    /// shipped in the app.
    func loadInstalled(notOlderThan bundled: MaintenanceCatalog) -> MaintenanceCatalog? {
        guard let data = try? Data(contentsOf: installedURL) else { return nil }
        guard let catalog = try? CatalogLoader.load(data: data) else { return nil }
        guard catalog.schemaVersion == bundled.schemaVersion else { return nil }
        guard CatalogUpdateService.isNewer(catalog.catalogVersion, than: bundled.catalogVersion)
            || catalog.catalogVersion == bundled.catalogVersion else { return nil }
        // Strict, matching both the CI gate and what the updater accepted in
        // the first place. A file that no longer validates is a file that was
        // tampered with or truncated after installation.
        guard CatalogValidator.validate(catalog).isEmpty else { return nil }
        return catalog
    }

    /// Writes a validated catalog into place atomically.
    func install(_ data: Data) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let staging = directory.appendingPathComponent("odomind-catalog.staged.json")
        try data.write(to: staging, options: .atomic)
        // `replaceItemAt` is the atomic swap; the staged file either becomes
        // the live one or does not, with nothing in between.
        if FileManager.default.fileExists(atPath: installedURL.path) {
            _ = try FileManager.default.replaceItemAt(installedURL, withItemAt: staging)
        } else {
            try FileManager.default.moveItem(at: staging, to: installedURL)
        }
    }

    func removeInstalled() {
        try? FileManager.default.removeItem(at: installedURL)
    }
}

/// Fetches reviewed catalog updates.
///
/// **The trust model, stated plainly.** Authenticity comes from TLS to a
/// pinned host: Odomind will only talk to `catalogHost` over HTTPS, and the
/// system's certificate validation is what says the manifest came from that
/// host. The SHA-256 in the manifest proves the catalog file matches the
/// manifest that described it — it is an integrity check against a truncated
/// or corrupted download, and it is **not** an independent signature, because
/// the manifest and the hash come from the same place. Anyone who could serve
/// a forged manifest could serve a matching hash. Upgrading that would mean a
/// detached signature over the manifest verified against a public key compiled
/// into the app; that is not built, and this comment is here so nobody reads
/// the checksum as though it were.
///
/// What the checksum *does* buy is real: a partial download, a proxy-mangled
/// body or a truncated file is caught before anything is installed.
struct CatalogUpdateService {
    /// The only host Odomind will fetch a catalog from.
    static let catalogHost = "raw.githubusercontent.com"
    static let manifestURL = URL(
        string: "https://raw.githubusercontent.com/BKimble1/Odomind/catalog/manifest.json"
    )!
    /// Refuses anything implausible before it is read into memory.
    static let maximumCatalogBytes = 8 * 1024 * 1024

    let store: CatalogUpdateStore
    let session: URLSession
    let manifestURL: URL

    init(
        store: CatalogUpdateStore = CatalogUpdateStore(),
        session: URLSession = CatalogUpdateService.makeSession(),
        manifestURL: URL = CatalogUpdateService.manifestURL
    ) {
        self.store = store
        self.session = session
        self.manifestURL = manifestURL
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }

    /// Checks for, verifies and installs an update.
    ///
    /// Every failure leaves whatever was already installed exactly as it was.
    func check(against current: MaintenanceCatalog) async -> CatalogUpdateResult {
        guard manifestURL.scheme == "https" else {
            return .rejected("The update location is not secure.")
        }

        let manifest: CatalogManifest
        do {
            let (data, response) = try await session.data(from: manifestURL)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return .unreachable("The update service did not answer.")
            }
            manifest = try CatalogLoader.makeDecoder().decode(CatalogManifest.self, from: data)
        } catch is DecodingError {
            return .rejected("The update service returned something Odomind could not read.")
        } catch {
            return .unreachable("Odomind could not reach the update service.")
        }

        // Schema first: a catalog written for a newer Odomind is not a
        // downgrade candidate, it is simply not for this build.
        guard manifest.schemaVersion == current.schemaVersion else {
            return .rejected(
                "That update needs a newer version of Odomind. Your current catalog is unchanged."
            )
        }
        guard Self.isNewer(manifest.catalogVersion, than: current.catalogVersion) else {
            return .upToDate(version: current.catalogVersion)
        }
        guard manifest.url.scheme == "https", manifest.url.host == Self.catalogHost else {
            return .rejected("The update pointed somewhere Odomind does not fetch from.")
        }
        guard manifest.byteCount > 0, manifest.byteCount <= Self.maximumCatalogBytes else {
            return .rejected("The update is an implausible size.")
        }

        let payload: Data
        do {
            let (data, response) = try await session.data(from: manifest.url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return .unreachable("The update file could not be downloaded.")
            }
            payload = data
        } catch {
            return .unreachable("Odomind could not download the update.")
        }

        guard payload.count == manifest.byteCount else {
            return .rejected("The update did not download completely.")
        }
        guard Self.sha256Hex(payload) == manifest.sha256.lowercased() else {
            return .rejected("The update did not match its checksum, so Odomind discarded it.")
        }

        let candidate: MaintenanceCatalog
        do {
            candidate = try CatalogLoader.load(data: payload)
        } catch {
            return .rejected("The update was not a catalog Odomind could read.")
        }
        guard candidate.catalogVersion == manifest.catalogVersion,
              candidate.schemaVersion == current.schemaVersion else {
            return .rejected("The update did not describe itself consistently.")
        }
        // The same bar CI holds the bundled catalog to, warnings included —
        // which is what `--strict` means there. A downloaded catalog is
        // published data like any other, and holding it to a lower standard
        // than the one in the binary would make the gate meaningless: the
        // easiest way to ship an unreviewed value would be to publish it
        // rather than commit it.
        let findings = CatalogValidator.validate(candidate)
        guard findings.isEmpty else {
            return .rejected("The update failed Odomind's own checks, so it was discarded.")
        }

        do {
            try store.install(payload)
        } catch {
            return .rejected("Odomind could not save the update. Your current catalog is unchanged.")
        }
        return .installed(version: candidate.catalogVersion)
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Compares dotted version strings numerically, so 2026.10.2 is newer than
    /// 2026.9.10 — which string comparison gets wrong.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let left = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let right = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b }
        }
        return false
    }
}
