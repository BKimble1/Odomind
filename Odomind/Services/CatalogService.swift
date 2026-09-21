import Foundation
import OdomindCore

/// Loads the maintenance catalog and reports honestly on where it came from.
///
/// Odomind always has a catalog: one ships inside the app bundle and is the
/// floor. On top of that, `CatalogUpdateService` may have installed a newer
/// reviewed one, which is loaded in preference — but only if it parses, passes
/// the same validator CI runs, and is not older than the bundled copy. Anything
/// else and the bundled catalog is used, which is what makes a bad download a
/// non-event rather than a broken app.
///
/// Not actor-isolated: it reads one file at init and never mutates afterwards,
/// so it is safe to construct anywhere — including as a default argument.
final class CatalogService: @unchecked Sendable {
    enum LoadState: Equatable {
        case loaded(MaintenanceCatalog)
        case failed(String)

        var catalog: MaintenanceCatalog? {
            if case .loaded(let catalog) = self { return catalog }
            return nil
        }

        var failureMessage: String? {
            if case .failed(let message) = self { return message }
            return nil
        }
    }

    let state: LoadState
    /// True when the catalog in use came from an installed update rather than
    /// the app bundle. Drives the wording in Settings and nothing else.
    let isInstalledUpdate: Bool

    init(loader: () throws -> MaintenanceCatalog = { try CatalogLoader.loadBundled() }) {
        do {
            state = .loaded(try loader())
        } catch let error as CatalogLoadError {
            state = .failed(error.message)
        } catch {
            state = .failed(String(describing: error))
        }
        isInstalledUpdate = false
    }

    /// The loader a live launch uses: an installed update if there is a good
    /// one, the bundled catalog otherwise.
    static func live(store: CatalogUpdateStore = CatalogUpdateStore()) -> CatalogService {
        let bundled = CatalogService()
        guard let bundledCatalog = bundled.catalog,
              let installed = store.loadInstalled(notOlderThan: bundledCatalog)
        else { return bundled }
        return CatalogService(installed: installed)
    }

    private init(installed: MaintenanceCatalog) {
        state = .loaded(installed)
        isInstalledUpdate = true
    }

    var catalog: MaintenanceCatalog? { state.catalog }

    /// What to tell the owner about catalog freshness.
    var updateStatus: CatalogUpdateStatus {
        switch state {
        case .loaded(let catalog):
            return isInstalledUpdate
                ? .installed(version: catalog.catalogVersion, publishedOn: catalog.publishedOn)
                : .bundled(version: catalog.catalogVersion, publishedOn: catalog.publishedOn)
        case .failed(let message):
            return .unavailable(message)
        }
    }
}

enum CatalogUpdateStatus: Equatable {
    /// The catalog that shipped inside this build of the app.
    case bundled(version: String, publishedOn: Date)
    /// A reviewed update that was downloaded, validated and installed.
    case installed(version: String, publishedOn: Date)
    case unavailable(String)

    var headline: String {
        switch self {
        case .bundled(let version, _), .installed(let version, _):
            return "Catalog \(version)"
        case .unavailable:
            return "Catalog unavailable"
        }
    }

    var detail: String {
        switch self {
        case .bundled:
            return """
            This is the catalog that shipped inside Odomind. Nothing has been downloaded over it.
            """
        case .installed(_, let publishedOn):
            return """
            Downloaded and installed after passing the same checks Odomind's own build runs. \
            Published \(Format.date(publishedOn)).
            """
        case .unavailable(let message):
            return message
        }
    }
}
