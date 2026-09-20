import Foundation
import OdomindCore

/// Loads the maintenance catalog and reports honestly on where it came from.
///
/// This version ships one catalog inside the app bundle. There is no update
/// service, and the app says exactly that rather than showing a "live database"
/// badge it cannot back up. `CatalogUpdateStatus` is the single place that
/// wording lives, so adding real updates later means changing one type.
@MainActor
final class CatalogService {
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

    private(set) var state: LoadState

    init(loader: () throws -> MaintenanceCatalog = { try CatalogLoader.loadBundled() }) {
        do {
            state = .loaded(try loader())
        } catch let error as CatalogLoadError {
            state = .failed(error.message)
        } catch {
            state = .failed(String(describing: error))
        }
    }

    var catalog: MaintenanceCatalog? { state.catalog }

    /// What to tell the owner about catalog freshness.
    var updateStatus: CatalogUpdateStatus {
        switch state {
        case .loaded(let catalog):
            return .bundled(version: catalog.catalogVersion, publishedOn: catalog.publishedOn)
        case .failed(let message):
            return .unavailable(message)
        }
    }
}

enum CatalogUpdateStatus: Equatable {
    /// The catalog that shipped inside this build of the app.
    case bundled(version: String, publishedOn: Date)
    case unavailable(String)

    var headline: String {
        switch self {
        case .bundled(let version, _):
            return "Catalog \(version)"
        case .unavailable:
            return "Catalog unavailable"
        }
    }

    var detail: String {
        switch self {
        case .bundled:
            return """
            This catalog ships inside Odomind. There is no update service yet, so it changes only when \
            you install a new version of the app. Odomind will not tell you it is checking for updates \
            when it is not.
            """
        case .unavailable(let message):
            return message
        }
    }
}
