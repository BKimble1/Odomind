import SwiftUI
import StoreKit
import OdomindCore

/// System, Light or Dark — stored, and applied everywhere.
struct AppearanceSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section {
                ForEach(AppearancePreference.allCases, id: \.self) { option in
                    Button {
                        model.setAppearance(option)
                    } label: {
                        HStack(spacing: Theme.Spacing.medium) {
                            Image(systemName: option.symbolName)
                                .foregroundStyle(Theme.Palette.secondaryText)
                                .frame(width: 24)
                            Text(option.displayName)
                                .foregroundStyle(Theme.Palette.primaryText)
                            Spacer()
                            if model.appearance == option {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.Palette.accent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(model.appearance == option ? [.isButton, .isSelected] : .isButton)
                    .accessibilityIdentifier("appearance.\(option.rawValue)")
                }
            } footer: {
                Text("System follows your device setting. Your choice applies to every screen, including sheets and the subscription screen, and is remembered between launches.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// What Odomind does with the calendar.
struct CalendarSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section {
                Stepper(
                    "Look ahead \(model.preferences.calendar.projectionMonths) months",
                    value: Binding(
                        get: { model.preferences.calendar.projectionMonths },
                        set: { newValue in model.updatePreferences { $0.calendar.projectionMonths = newValue } }
                    ),
                    in: 1...24
                )
                .accessibilityIdentifier("calendarSettings.horizon")
            } header: {
                Text("How far ahead")
            } footer: {
                Text("A job due at a mileage moves every time you add a reading, so Odomind projects a bounded window rather than an endless series of dates that will be wrong next month.")
            }

            Section {
                Toggle(
                    "Add an alert to exported events",
                    isOn: Binding(
                        get: { model.preferences.calendar.addAlarmsToExportedEvents },
                        set: { newValue in
                            model.updatePreferences { $0.calendar.addAlarmsToExportedEvents = newValue }
                        }
                    )
                )
            } header: {
                Text("Exported events")
            } footer: {
                // The duplicate-alert problem, named and defaulted sensibly
                // rather than left for the owner to discover twice a month.
                Text(
                    model.snapshot.settings.reminders.remindersEnabled
                        ? "Odomind reminders are on, so exported events are added without their own alert by default. Turning this on means you will hear about the same job twice."
                        : "Exported events can carry their own alert the morning before. Odomind's own reminders are currently off."
                )
            }

            Section {
                QuietNote(
                    text: "Odomind asks only for permission to add events. It cannot read your calendar, so it cannot update or remove what it has added, and it does not claim to.",
                    symbolName: "lock.shield"
                )
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Miles or kilometres, per vehicle.
struct UnitsSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section {
                ForEach(model.snapshot.vehicles) { vehicle in
                    Picker(
                        vehicle.displayName,
                        selection: Binding(
                            get: { vehicle.displayUnit },
                            set: { newValue in model.setDisplayUnit(newValue, for: vehicle.id) }
                        )
                    ) {
                        Text("Miles").tag(DistanceUnit.miles)
                        Text("Kilometres").tag(DistanceUnit.kilometers)
                    }
                }
            } header: {
                Text("Distance")
            } footer: {
                Text("Stored per vehicle, so a household can keep one car in miles and another in kilometres. Readings you have already entered keep the unit they were entered in.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Units")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Subscription status and management.
struct ProSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationRouter.self) private var router

    @State private var restoreMessage: String?

    var body: some View {
        List {
            Section {
                switch model.entitlements.status {
                case .unknown:
                    HStack {
                        ProgressView()
                        Text("Checking with the App Store…")
                            .foregroundStyle(Theme.Palette.secondaryText)
                    }
                case .notSubscribed:
                    Label("Odomind Pro is not active", systemImage: "circle")
                        .foregroundStyle(Theme.Palette.secondaryText)
                    Button("See what Pro adds") { router.presentPaywall = true }
                        .accessibilityIdentifier("proSettings.openPaywall")
                case .subscribed(let expiresOn, let inGrace):
                    Label("Odomind Pro is active", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(Theme.Palette.accent)
                    if inGrace {
                        QuietNote(
                            text: "Apple is retrying your payment. Pro stays on while that happens.",
                            symbolName: "creditcard"
                        )
                    } else if let expiresOn {
                        ValueRow(label: "Renews or ends", value: Format.date(expiresOn))
                    }
                }
            } header: {
                Text("Status")
            }

            Section {
                if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                    Link("Manage subscription", destination: url)
                        .accessibilityIdentifier("proSettings.manage")
                }
                Button("Restore purchases") {
                    Task {
                        switch await model.entitlements.restore() {
                        case .purchased: restoreMessage = "Restored."
                        case .failed(let reason): restoreMessage = reason
                        case .pending, .cancelled: restoreMessage = nil
                        }
                    }
                }
                .accessibilityIdentifier("proSettings.restore")
                if let restoreMessage {
                    Text(restoreMessage)
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.secondaryText)
                }
            }

            Section {
                ValueRow(
                    label: "Vehicles",
                    value: model.isPro
                        ? "\(model.ownedVehicles.count) · unlimited"
                        : "\(model.ownedVehicles.count) of \(model.freeVehicleAllowance)"
                )
                if let grandfathered = model.preferences.pro.grandfatheredVehicleAllowance,
                   grandfathered > ProPolicy.freeVehicleAllowance {
                    QuietNote(
                        text: "You had \(grandfathered) vehicles before Odomind introduced a free-plan limit, so that is your allowance. It does not shrink.",
                        symbolName: "checkmark.shield"
                    )
                }
            } header: {
                Text("Your plan")
            } footer: {
                Text(ProPolicy.lapsePromise)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Odomind Pro")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.entitlements.refreshEntitlement() }
    }
}

/// The sample vehicle, in its own explicit place rather than beside the
/// owner's real data.
struct SampleDataView: View {
    @Environment(AppModel.self) private var model
    @State private var showingRemove = false

    var body: some View {
        List {
            Section {
                if model.hasDemoContent {
                    Button("Remove the sample vehicle", role: .destructive) { showingRemove = true }
                        .accessibilityIdentifier("sample.remove")
                } else {
                    Button("Add a sample vehicle") { model.addDemoContent() }
                        .accessibilityIdentifier("sample.add")
                }
            } header: {
                Text("Preview")
            } footer: {
                Text(model.demoDisclaimer ?? "Sample content is fictional and clearly marked. It is left out of your vehicle count, your reminders, calendar exports and reports, and removing it never touches your own records.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Sample vehicle")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Remove the sample vehicle?", isPresented: $showingRemove, titleVisibility: .visible) {
            Button("Remove sample data", role: .destructive) {
                Task { await model.removeDemoContent() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your own vehicles and records are not affected.")
        }
    }
}

/// Where maintenance guidance comes from, and how to refresh it.
struct CatalogUpdateSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationRouter.self) private var router

    @State private var isChecking = false
    @State private var result: CatalogUpdateResult?

    var body: some View {
        List {
            Section {
                ValueRow(label: "In use", value: model.catalogService.updateStatus.headline)
                Text(model.catalogService.updateStatus.detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.secondaryText)
            } header: {
                Text("Current")
            }

            Section {
                Toggle(
                    "Check automatically",
                    isOn: Binding(
                        get: { model.preferences.catalogUpdates.automaticUpdatesEnabled },
                        set: { newValue in
                            if newValue && !model.isPro {
                                router.presentPaywall = true
                            } else {
                                model.updatePreferences { $0.catalogUpdates.automaticUpdatesEnabled = newValue }
                            }
                        }
                    )
                )
                .accessibilityIdentifier("catalogUpdates.automatic")

                Button {
                    Task { await check() }
                } label: {
                    HStack {
                        Text("Check now")
                        if isChecking { Spacer(); ProgressView() }
                    }
                }
                .disabled(isChecking)
                .accessibilityIdentifier("catalogUpdates.checkNow")

                if let last = model.preferences.catalogUpdates.lastCheckedOn {
                    ValueRow(label: "Last checked", value: Format.dateAndTime(last))
                }
                if let message = resultMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.secondaryText)
                }
            } header: {
                Text("Updates")
            } footer: {
                Text("Automatic checks are part of Odomind Pro and happen occasionally while you are using the app — never at launch, and never in a loop. Manual checks are always available.")
            }

            if model.openProposalCount > 0 {
                Section {
                    Button("Review \(model.openProposalCount) schedule change\(model.openProposalCount == 1 ? "" : "s")") {
                        router.openProposals()
                    }
                    .accessibilityIdentifier("catalogUpdates.reviewProposals")
                } footer: {
                    Text("An update never changes a schedule you set yourself, and never silently changes one you did not. Changed guidance is parked here for you to accept or ignore.")
                }
            }

            Section {
                QuietNote(
                    text: "Odomind fetches updates over HTTPS from one fixed location and checks the file against the checksum published beside it. That catches a corrupted or partial download. It is not a signature — the checksum and the file come from the same place — and Odomind does not claim otherwise.",
                    symbolName: "lock.shield"
                )
            } header: {
                Text("How this is trusted")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Maintenance updates")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var resultMessage: String? {
        switch result {
        case .none:
            return model.preferences.catalogUpdates.lastFailureMessage
        case .upToDate(let version):
            return "Up to date — catalog \(version)."
        case .installed(let version):
            return "Installed catalog \(version). It takes effect the next time Odomind opens."
        case .rejected(let reason), .unreachable(let reason):
            return reason
        }
    }

    private func check() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        result = await model.checkForCatalogUpdate()
    }
}
