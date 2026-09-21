import CoreLocation
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

    /// Records that the welcome permission questions have been put.
    ///
    /// Set whether or not anything was granted: a refusal is an answer, and
    /// asking again next launch is how an app trains people to dismiss it.
    func markPermissionSetupSeen() {
        guard !preferences.hasSeenPermissionSetup else { return }
        updatePreferences { $0.hasSeenPermissionSetup = true }
    }

    /// Whether an owner upgrading from an earlier build should be offered a
    /// short catch-up rather than the whole welcome sequence.
    ///
    /// True only when there is a garage already — a fresh install goes through
    /// onboarding proper — and when something is still unasked.
    var shouldOfferPermissionCatchUp: Bool {
        guard !preferences.hasSeenPermissionSetup else { return false }
        guard !ownedVehicles.isEmpty else { return false }
        let remindersUnset = !snapshot.settings.reminders.remindersEnabled
        let locationUnset = shoppingLocation.authorizationStatus == .notDetermined
        return remindersUnset || locationUnset
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

extension AppModel {
    /// Changes the unit a vehicle's readings are shown in.
    ///
    /// Readings keep the unit they were entered in; this only changes what
    /// new entry and display use, so nothing already recorded is reinterpreted.
    func setDisplayUnit(_ unit: DistanceUnit, for vehicleID: UUID) {
        guard var vehicle = snapshot.vehicle(id: vehicleID), vehicle.displayUnit != unit else { return }
        vehicle.displayUnit = unit
        updateVehicle(vehicle, declaredTypicalDistance: snapshot.declaredTypicalDistances[vehicleID])
    }

    /// Records how the owner wants this vehicle pictured.
    func setArtwork(_ artwork: VehicleArtworkPreference, for vehicleID: UUID) {
        guard var vehicle = snapshot.vehicle(id: vehicleID) else { return }
        vehicle.artwork = artwork
        updateVehicle(vehicle, declaredTypicalDistance: snapshot.declaredTypicalDistances[vehicleID])
    }
}
