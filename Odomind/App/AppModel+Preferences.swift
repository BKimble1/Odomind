import Foundation
import OdomindCore

extension AppModel {
    var preferences: AppPreferences { snapshot.settings.preferences }

    /// Every preference change goes through here, so it lands in the store and
    /// the snapshot the screens read from in one step.
    func updatePreferences(_ update: (inout AppPreferences) -> Void) {
        var settings = snapshot.settings
        update(&settings.preferences)
        persist(settings: settings)
    }

    var appearance: AppearancePreference { preferences.appearance }

    func setAppearance(_ appearance: AppearancePreference) {
        updatePreferences { $0.appearance = appearance }
    }

    /// Vehicles the owner added themselves. The sample never counts — not
    /// towards the free allowance, not towards the garage's own headline.
    var ownedVehicles: [Vehicle] {
        snapshot.vehicles.filter { !$0.isDemo }
    }

    /// Records the garage size the owner already had, once, so introducing a
    /// free-tier limit can never lock them out of a vehicle they already
    /// entered.
    ///
    /// Runs on the first Build 2 launch and never again: `hasRecorded` is the
    /// latch. Deleting a vehicle afterwards does not shrink the allowance,
    /// because the point is what they had when the rule changed, not what they
    /// have now.
    func recordGrandfatheredAllowanceIfNeeded() {
        guard !preferences.pro.hasRecordedGrandfatheredAllowance else { return }
        let existing = ownedVehicles.count
        updatePreferences {
            $0.pro.hasRecordedGrandfatheredAllowance = true
            $0.pro.grandfatheredVehicleAllowance = existing
        }
    }
}
