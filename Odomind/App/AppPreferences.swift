import Foundation
import SwiftUI

/// How the owner wants the app to look, regardless of the system setting.
enum AppearancePreference: String, Codable, Sendable, CaseIterable, Hashable {
    case system
    case light
    case dark

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var symbolName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    /// `nil` means "follow the system", which is the default and what SwiftUI
    /// wants for `preferredColorScheme`.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// What Odomind does with the owner's calendar.
///
/// One-off export needs no stored state beyond what a plan item already keeps.
/// Managed updates need an owned calendar and a mapping, and both are gated on
/// full access the owner granted explicitly.
struct CalendarPreferences: Codable, Hashable, Sendable {
    /// Pro's managed sync. Off unless the owner turns it on *and* grants full
    /// access — the two are checked separately, because a granted permission
    /// is not a request to start writing.
    var managedSyncEnabled: Bool
    /// Identifier of the calendar Odomind created and owns. Odomind only ever
    /// manages events in this calendar.
    var managedCalendarIdentifier: String?
    /// How far ahead managed sync and the in-app agenda project.
    var projectionMonths: Int
    /// When both app reminders and calendar alarms are on, one of them has to
    /// give way or the owner gets two pings for the same job.
    var addAlarmsToExportedEvents: Bool

    init(
        managedSyncEnabled: Bool = false,
        managedCalendarIdentifier: String? = nil,
        projectionMonths: Int = 6,
        addAlarmsToExportedEvents: Bool = false
    ) {
        self.managedSyncEnabled = managedSyncEnabled
        self.managedCalendarIdentifier = managedCalendarIdentifier
        self.projectionMonths = min(max(projectionMonths, 1), 24)
        self.addAlarmsToExportedEvents = addAlarmsToExportedEvents
    }

    static let `default` = CalendarPreferences()

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            managedSyncEnabled: try container.decodeIfPresent(Bool.self, forKey: .managedSyncEnabled) ?? false,
            managedCalendarIdentifier: try container.decodeIfPresent(String.self, forKey: .managedCalendarIdentifier),
            projectionMonths: try container.decodeIfPresent(Int.self, forKey: .projectionMonths) ?? 6,
            addAlarmsToExportedEvents: try container.decodeIfPresent(Bool.self, forKey: .addAlarmsToExportedEvents) ?? false
        )
    }
}

/// Remote catalog refresh.
struct CatalogUpdatePreferences: Codable, Hashable, Sendable {
    /// Pro. Off for everyone until they turn it on; the bundled catalog is
    /// always there either way.
    var automaticUpdatesEnabled: Bool
    var lastCheckedOn: Date?
    var lastInstalledVersion: String?
    /// What went wrong last time, kept so Settings can say so rather than
    /// showing a check that silently never succeeds.
    var lastFailureMessage: String?

    init(
        automaticUpdatesEnabled: Bool = false,
        lastCheckedOn: Date? = nil,
        lastInstalledVersion: String? = nil,
        lastFailureMessage: String? = nil
    ) {
        self.automaticUpdatesEnabled = automaticUpdatesEnabled
        self.lastCheckedOn = lastCheckedOn
        self.lastInstalledVersion = lastInstalledVersion
        self.lastFailureMessage = lastFailureMessage
    }

    static let `default` = CatalogUpdatePreferences()

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            automaticUpdatesEnabled: try container.decodeIfPresent(Bool.self, forKey: .automaticUpdatesEnabled) ?? false,
            lastCheckedOn: try container.decodeIfPresent(Date.self, forKey: .lastCheckedOn),
            lastInstalledVersion: try container.decodeIfPresent(String.self, forKey: .lastInstalledVersion),
            lastFailureMessage: try container.decodeIfPresent(String.self, forKey: .lastFailureMessage)
        )
    }
}

/// What Odomind remembers about the owner's entitlement, as distinct from what
/// StoreKit says right now.
///
/// StoreKit is the authority on whether a subscription is active. Nothing here
/// grants Pro. What it does hold is the one thing StoreKit cannot know: how
/// many vehicles the owner already had before a limit existed.
struct ProPreferences: Codable, Hashable, Sendable {
    /// Vehicles the owner had at the moment Build 2 first ran, so introducing
    /// a free-tier limit can never make an existing vehicle inaccessible.
    ///
    /// `nil` means the migration has not run yet. Zero is a real answer and is
    /// not the same as `nil`.
    var grandfatheredVehicleAllowance: Int?
    /// Set once the Build 2 migration has looked at the garage, so a later
    /// deletion cannot re-run it and shrink the allowance.
    var hasRecordedGrandfatheredAllowance: Bool

    init(
        grandfatheredVehicleAllowance: Int? = nil,
        hasRecordedGrandfatheredAllowance: Bool = false
    ) {
        self.grandfatheredVehicleAllowance = grandfatheredVehicleAllowance
        self.hasRecordedGrandfatheredAllowance = hasRecordedGrandfatheredAllowance
    }

    static let `default` = ProPreferences()

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            grandfatheredVehicleAllowance: try container.decodeIfPresent(Int.self, forKey: .grandfatheredVehicleAllowance),
            hasRecordedGrandfatheredAllowance: try container.decodeIfPresent(Bool.self, forKey: .hasRecordedGrandfatheredAllowance) ?? false
        )
    }
}

/// Everything Build 2 added to settings, in one JSON column.
///
/// The architecture note says to prefer a `Codable` change with tolerant
/// decoding over a store migration per field, and this is that: one additive
/// `Data` property on `StoredSettings` carries every new preference, and every
/// member decodes missing keys to its default. A Build 1 store has an empty
/// column, which decodes to `.default` — so upgrading changes nothing the
/// owner did not ask for.
struct AppPreferences: Codable, Hashable, Sendable {
    var appearance: AppearancePreference
    var calendar: CalendarPreferences
    var catalogUpdates: CatalogUpdatePreferences
    var pro: ProPreferences
    /// The one-time note about where History went. Skippable, shown once.
    var hasSeenCalendarIntroduction: Bool
    /// Whether the welcome sequence's permission questions have been put.
    ///
    /// Tracked separately from whether permission was *granted*, so a refusal
    /// is remembered as an answer rather than re-asked at every launch. An
    /// existing owner upgrading from Build 2 has this false and is offered a
    /// short optional catch-up, not the whole flow again.
    var hasSeenPermissionSetup: Bool

    init(
        appearance: AppearancePreference = .system,
        calendar: CalendarPreferences = .default,
        catalogUpdates: CatalogUpdatePreferences = .default,
        pro: ProPreferences = .default,
        hasSeenCalendarIntroduction: Bool = false,
        hasSeenPermissionSetup: Bool = false
    ) {
        self.appearance = appearance
        self.calendar = calendar
        self.catalogUpdates = catalogUpdates
        self.pro = pro
        self.hasSeenCalendarIntroduction = hasSeenCalendarIntroduction
        self.hasSeenPermissionSetup = hasSeenPermissionSetup
    }

    static let `default` = AppPreferences()

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            appearance: try container.decodeIfPresent(AppearancePreference.self, forKey: .appearance) ?? .system,
            calendar: try container.decodeIfPresent(CalendarPreferences.self, forKey: .calendar) ?? .default,
            catalogUpdates: try container.decodeIfPresent(CatalogUpdatePreferences.self, forKey: .catalogUpdates) ?? .default,
            pro: try container.decodeIfPresent(ProPreferences.self, forKey: .pro) ?? .default,
            hasSeenCalendarIntroduction: try container.decodeIfPresent(Bool.self, forKey: .hasSeenCalendarIntroduction) ?? false,
            hasSeenPermissionSetup: try container.decodeIfPresent(Bool.self, forKey: .hasSeenPermissionSetup) ?? false
        )
    }
}
