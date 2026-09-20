import Foundation
import Observation
import OdomindCore

/// Where the app should be.
///
/// Tab selection and per-tab navigation live here so a notification tap or a
/// deep link can land on the right screen without every view having to know
/// about routing.
@MainActor
@Observable
final class NavigationRouter {
    enum Tab: String, Hashable, CaseIterable {
        case today
        case maintenance
        case garage
        case history

        var title: String {
            switch self {
            case .today: return "Today"
            case .maintenance: return "Maintenance"
            case .garage: return "Garage"
            case .history: return "History"
            }
        }

        var symbolName: String {
            switch self {
            case .today: return "car.side"
            case .maintenance: return "wrench.and.screwdriver"
            case .garage: return "building.columns"
            case .history: return "clock.arrow.circlepath"
            }
        }
    }

    var selectedTab: Tab = .today
    var maintenancePath: [MaintenanceRoute] = []
    var garagePath: [GarageRoute] = []
    var historyPath: [HistoryRoute] = []

    /// Requested by a deep link; the Today screen picks it up and presents.
    var pendingVehicleSelection: UUID?
    var presentMileageEntry = false
    var presentServiceLog = false

    func follow(_ link: DeepLink) {
        switch link {
        case .vehicle(let id):
            pendingVehicleSelection = id
            selectedTab = .today
        case .task(let vehicleID, let planItemID):
            pendingVehicleSelection = vehicleID
            selectedTab = .maintenance
            maintenancePath = [.task(planItemID)]
        case .updateMileage(let vehicleID):
            pendingVehicleSelection = vehicleID
            selectedTab = .today
            presentMileageEntry = true
        case .logService(let vehicleID):
            pendingVehicleSelection = vehicleID
            selectedTab = .today
            presentServiceLog = true
        }
    }

    func resetPaths() {
        maintenancePath = []
        garagePath = []
        historyPath = []
    }
}

enum MaintenanceRoute: Hashable {
    case task(UUID)
    case addTask
    case customTask
    case proposals
}

enum GarageRoute: Hashable {
    case vehicle(UUID)
    case specifications(UUID)
    case configuration(UUID)
    case odometerHistory(UUID)
    case settings
    case reminders
    case dataSources
    case backup
    case about
    case privacy
    case diagnostics
}

enum HistoryRoute: Hashable {
    case record(UUID)
    case export
}
