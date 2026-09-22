import SwiftUI
import OdomindCore

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationRouter.self) private var router

    var body: some View {
        @Bindable var model = model
        @Bindable var router = router

        Group {
            if model.needsOnboarding {
                OnboardingView()
            } else {
                TabView(selection: $router.selectedTab) {
                    tab(.home) { HomeView() }
                    tab(.jobs) { JobsView() }
                    tab(.garage) { GarageView() }
                    tab(.calendar) { CalendarView() }
                }
            }
        }
        .tint(Theme.Palette.accent)
        .alert(
            model.alert?.title ?? "",
            isPresented: Binding(
                get: { model.alert != nil },
                set: { isPresented in if !isPresented { model.alert = nil } }
            ),
            presenting: model.alert
        ) { _ in
            Button("OK", role: .cancel) { model.alert = nil }
        } message: { alert in
            Text([alert.message, alert.recoverySuggestion].compactMap { $0 }.joined(separator: "\n\n"))
        }
        .sheet(isPresented: $router.presentPaywall) {
            PaywallView()
        }
        .onChange(of: router.pendingVehicleSelection) { _, newValue in
            guard let newValue, model.snapshot.vehicle(id: newValue) != nil else { return }
            model.selectVehicle(newValue)
            router.pendingVehicleSelection = nil
        }
    }

    private func tab<Content: View>(
        _ tab: NavigationRouter.Tab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .tabItem { Label(tab.title, systemImage: tab.symbolName) }
            .tag(tab)
    }
}

/// Every destination any stack can reach, registered in one place.
///
/// Settings is reachable from Calendar's gear and from a Pro prompt raised on
/// another tab, and a job opens from Home, Jobs and Calendar alike. Registering
/// the same set on each stack means a route value works wherever it is pushed,
/// rather than silently doing nothing because the stack it landed in had never
/// heard of it.
struct OdomindDestinations: ViewModifier {
    func body(content: Content) -> some View {
        content
            .navigationDestination(for: JobRoute.self) { route in
                switch route {
                case .task(let id): TaskDetailView(planItemID: id)
                case .addTask: AddTaskView()
                case .customTask: CustomTaskEditor()
                case .proposals: ProposalsView()
                case .parts(let destination): PartsView(destination: destination)
                case .untracked(let definitionID): UntrackedJobView(definitionID: definitionID)
                }
            }
            .navigationDestination(for: VehicleRoute.self) { route in
                switch route {
                case .vehicle(let id): VehicleDetailView(vehicleID: id)
                case .specifications(let id): SpecificationsView(vehicleID: id)
                case .configuration(let id): ConfigurationEditor(vehicleID: id)
                case .odometerHistory(let id): OdometerHistoryView(vehicleID: id)
                case .artwork(let id): VehicleArtworkPicker(vehicleID: id)
                case .spending(let id): SpendingReportView(vehicleID: id)
                }
            }
            .navigationDestination(for: RecordRoute.self) { route in
                switch route {
                case .record(let id): ServiceRecordDetailView(recordID: id)
                case .export: ExportView()
                }
            }
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .settings: SettingsView()
                case .reminders: ReminderSettingsView()
                case .appearance: AppearanceSettingsView()
                case .calendar: CalendarSettingsView()
                case .units: UnitsSettingsView()
                case .dataSources: DataSourcesView()
                case .backup: BackupView()
                case .about: AboutView()
                case .privacy: PrivacyView()
                case .diagnostics: DiagnosticsView()
                case .pro: ProSettingsView()
                case .sampleData: SampleDataView()
                case .catalogUpdates: CatalogUpdateSettingsView()
                }
            }
    }
}

extension View {
    func odomindDestinations() -> some View {
        modifier(OdomindDestinations())
    }
}

/// The selected vehicle, shown at the top of Home, Jobs and Calendar.
///
/// It is a switcher only when there is somewhere to switch to. The name shows
/// either way, which is the change Build 3 asked for: "which car is this
/// about" is the first question every screen underneath answers, and hiding
/// the control entirely for the single-vehicle owner — the common case, now
/// that the free allowance is one — left that question answered nowhere once
/// Home stopped repeating the name in a card of its own.
struct VehiclePickerBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let selected = model.dashboardVehicle {
            if model.hasVehicleChoice {
                Menu {
                    ForEach(model.snapshot.vehicles) { vehicle in
                        Button {
                            model.showVehicle(vehicle.id)
                        } label: {
                            if vehicle.id == selected.id {
                                Label(vehicle.displayName, systemImage: "checkmark")
                            } else {
                                Text(vehicle.displayName)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: Theme.Spacing.tight) {
                        Text(selected.displayName)
                            .font(.body.weight(.medium))
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                            .multilineTextAlignment(.leading)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                    }
                }
                .accessibilityLabel(Text("Selected vehicle: \(selected.displayName). Double tap to switch."))
                .accessibilityIdentifier("vehiclePicker")
            } else {
                // No chevron, because there is nothing behind it. A control
                // that opens a menu containing only the thing you are already
                // looking at is a decoy.
                Text(selected.displayName)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.Palette.primaryText)
                    // Two lines rather than one, and shrink before truncating.
                    // A name cut to "Sa…" tells the owner nothing; a name over
                    // two lines still tells them which car.
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.leading)
                    .accessibilityLabel(Text("Vehicle: \(selected.displayName)"))
                    .accessibilityIdentifier("vehiclePicker")
            }
        }
    }
}

/// Shown on a tab when there is no vehicle to show. Should be rare, because
/// onboarding runs first, but a deleted last vehicle lands here.
struct NoVehicleView: View {
    var body: some View {
        ContentUnavailableView {
            Label("No vehicle yet", systemImage: "car.side")
        } description: {
            Text("Add a vehicle in Garage to start tracking maintenance.")
        }
    }
}
