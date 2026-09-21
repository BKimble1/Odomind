import Foundation
import Observation
import SwiftUI
import OdomindCore

/// Where the app should be.
///
/// Tab selection and per-tab navigation live here so a notification tap or a
/// deep link can land on the right screen without every view having to know
/// about routing.
/// Not actor-isolated so it can be created in the `App` struct's property
/// initializer. SwiftUI only ever reads and writes it from the main actor.
@Observable
final class NavigationRouter {
    /// Build 2's four tabs.
    ///
    /// History folded into Calendar: past work and future work are the same
    /// question asked in two directions, and keeping them apart meant a
    /// screen of filters over an empty state.
    enum Tab: String, Hashable, CaseIterable {
        case home
        case jobs
        case garage
        case calendar

        var title: String {
            switch self {
            case .home: return "Home"
            case .jobs: return "Jobs"
            case .garage: return "Garage"
            case .calendar: return "Calendar"
            }
        }

        var symbolName: String {
            switch self {
            case .home: return "house"
            case .jobs: return "wrench.and.screwdriver"
            // Not `building.columns`. A bank is not a garage, and the brief
            // was right that it made the screen read as an admin section.
            case .garage: return "car.2"
            case .calendar: return "calendar"
            }
        }
    }

    var selectedTab: Tab = .home

    // One path per tab. `NavigationPath` rather than a typed array because a
    // stack routinely mixes kinds — a job opened from Home leads to a vehicle's
    // specifications, and Settings can be reached from two different tabs.
    var homePath = NavigationPath()
    var jobsPath = NavigationPath()
    var garagePath = NavigationPath()
    var calendarPath = NavigationPath()

    /// Requested by a deep link; `RootView` picks it up and selects.
    var pendingVehicleSelection: UUID?
    var presentMileageEntry = false
    var presentServiceLog = false
    /// Set when something should open the paywall — a gated action, or the
    /// Pro row in Settings.
    var presentPaywall = false
    /// A day Calendar should open on, set by Home's week strip.
    var calendarSelectedDay: Date?

    func follow(_ link: DeepLink) {
        switch link {
        case .vehicle(let id):
            pendingVehicleSelection = id
            selectedTab = .garage
            garagePath = NavigationPath()
            garagePath.append(VehicleRoute.vehicle(id))
        case .task(let vehicleID, let planItemID):
            pendingVehicleSelection = vehicleID
            selectedTab = .jobs
            jobsPath = NavigationPath()
            jobsPath.append(JobRoute.task(planItemID))
        case .updateMileage(let vehicleID):
            pendingVehicleSelection = vehicleID
            selectedTab = .home
            presentMileageEntry = true
        case .logService(let vehicleID):
            pendingVehicleSelection = vehicleID
            selectedTab = .home
            presentServiceLog = true
        }
    }

    /// Opens a job from anywhere, in the tab the owner is already looking at.
    ///
    /// Pushing onto the current stack rather than jumping to Jobs keeps the
    /// back button meaning what it looks like it means.
    func openJob(_ planItemID: UUID) {
        let route = JobRoute.task(planItemID)
        switch selectedTab {
        case .home: homePath.append(route)
        case .jobs: jobsPath.append(route)
        case .garage: garagePath.append(route)
        case .calendar: calendarPath.append(route)
        }
    }

    func openSettings() {
        selectedTab = .calendar
        calendarPath.append(SettingsRoute.settings)
    }

    func openProposals() {
        selectedTab = .jobs
        jobsPath.append(JobRoute.proposals)
    }

    func resetPaths() {
        homePath = NavigationPath()
        jobsPath = NavigationPath()
        garagePath = NavigationPath()
        calendarPath = NavigationPath()
    }
}

/// Maintenance work, reachable from every tab.
enum JobRoute: Hashable {
    case task(UUID)
    case addTask
    case customTask
    case proposals
    /// The parts side of a job, or the standalone Parts search.
    ///
    /// Carries what the owner was actually looking for. Build 2 routed
    /// `parts(nil)` from Home's search field, so typing "oil filter" and
    /// tapping through arrived at an empty parts screen and the query had to
    /// be typed again. A route that drops its own subject is a route that
    /// makes the owner do the work twice.
    case parts(PartsDestination)
}

/// Everything the parts screen needs to open already knowing what it is for.
struct PartsDestination: Hashable, Sendable {
    /// The job this came from, when it came from one.
    var planItemID: UUID?
    /// What was typed, carried verbatim.
    var query: String?
    /// The catalogue category a job maps to — an oil change opens oil and
    /// filters, not a blank search.
    var category: String?

    init(planItemID: UUID? = nil, query: String? = nil, category: String? = nil) {
        self.planItemID = planItemID
        self.query = query
        self.category = category
    }

    static let blank = PartsDestination()
}

/// A vehicle and the screens that belong to it.
enum VehicleRoute: Hashable {
    case vehicle(UUID)
    case specifications(UUID)
    case configuration(UUID)
    case odometerHistory(UUID)
    case artwork(UUID)
    case spending(UUID)
}

/// Recorded work.
enum RecordRoute: Hashable {
    case record(UUID)
    case export
}

/// Everything under the gear.
///
/// A single enum used by whichever stack presents Settings, so the rows inside
/// it do not have to know which tab they were opened from.
enum SettingsRoute: Hashable {
    case settings
    case reminders
    case appearance
    case calendar
    case units
    case dataSources
    case backup
    case about
    case privacy
    case diagnostics
    case pro
    case sampleData
    case catalogUpdates
}
