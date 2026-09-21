import Foundation
import OdomindCore

extension AppModel {

    /// How many vehicles this owner may keep without Pro.
    ///
    /// One for anyone starting fresh. For anyone who was already using
    /// Odomind, whatever they had when the limit appeared — because a limit
    /// introduced in an update must never make a vehicle they already entered
    /// unreachable.
    var freeVehicleAllowance: Int {
        max(ProPolicy.freeVehicleAllowance, preferences.pro.grandfatheredVehicleAllowance ?? 0)
    }

    var isPro: Bool { entitlements.status.isActive }

    /// Whether another vehicle can be added right now.
    ///
    /// Deliberately permissive while StoreKit has not answered: a slow
    /// entitlement check must not look like a lapsed subscription.
    var canAddVehicle: Bool {
        if isPro { return true }
        if entitlements.status == .unknown { return true }
        return ownedVehicles.count < freeVehicleAllowance
    }

    /// The line under Add a vehicle, when there is something worth saying.
    ///
    /// Silent until it is relevant. Someone who has not reached the limit does
    /// not need to be told about it every time they open the garage.
    var vehicleAllowanceNotice: String? {
        guard !isPro, entitlements.status != .unknown else { return nil }
        let used = ownedVehicles.count
        let allowance = freeVehicleAllowance
        guard used > 0 else { return nil }

        if used >= allowance {
            let noun = allowance == 1 ? "vehicle" : "vehicles"
            return "The free plan covers \(allowance) \(noun), and you are using \(used). Odomind Pro removes the limit. Everything already here stays either way."
        }
        if allowance - used == 1 {
            return "One more vehicle on the free plan."
        }
        return nil
    }

    /// Whether a Pro-only action can run.
    ///
    /// The one place a premium gate is decided, so a lapse behaves the same
    /// everywhere: existing records stay readable and editable, core reminders
    /// keep working, and only new premium *actions* stop.
    func requiresPro(_ feature: ProFeature) -> Bool {
        !isPro
    }
}

/// The premium features, named so the paywall and the gates cannot disagree
/// about what is actually behind them.
enum ProFeature: String, CaseIterable, Hashable {
    case automaticCatalogUpdates
    case receiptScanning
    case spendingReports
    case unlimitedVehicles

    var title: String {
        switch self {
        case .automaticCatalogUpdates: return "Automatic maintenance updates"
        case .receiptScanning: return "Receipt scanning"
        case .spendingReports: return "Spending trends and reports"
        case .unlimitedVehicles: return "Unlimited vehicles"
        }
    }

    var detail: String {
        switch self {
        case .automaticCatalogUpdates:
            return "Odomind checks for reviewed changes to maintenance guidance and shows you what changed before anything moves. Your own schedules are never overwritten."
        case .receiptScanning:
            return "Read the date, shop and total off a receipt photo on your device, then check it before it is saved. Nothing is uploaded."
        case .spendingReports:
            return "See what you have spent by job, by month and by vehicle, and produce a service dossier you can hand to a buyer or a shop."
        case .unlimitedVehicles:
            return "Keep as many vehicles as you own."
        }
    }

    var symbolName: String {
        switch self {
        case .automaticCatalogUpdates: return "arrow.triangle.2.circlepath"
        case .receiptScanning: return "doc.text.viewfinder"
        case .spendingReports: return "chart.bar.xaxis"
        case .unlimitedVehicles: return "car.2"
        }
    }
}

enum ProPolicy {
    /// The free allowance for someone starting today.
    ///
    /// One. Everything a single-car owner needs is free and stays free; a
    /// second vehicle is the point where Odomind is doing ongoing work for a
    /// household rather than a person. Anyone who already had more keeps them:
    /// see `AppModel.freeVehicleAllowance`.
    static let freeVehicleAllowance = 1

    /// What Odomind promises about records when a subscription ends.
    ///
    /// Written once, quoted on the paywall and in Settings, so the promise
    /// cannot be worded more generously in one place than the other.
    static let lapsePromise = "If Pro ends, everything you have recorded stays on your device, stays editable, and your reminders keep working. Only new Pro actions stop."
}
