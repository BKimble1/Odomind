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
                case .parts(let planItemID): PartsView(planItemID: planItemID)
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

/// The vehicle switcher shown at the top of Home, Jobs and Calendar.
///
/// Hidden entirely when there is one real vehicle, so single-vehicle use never
/// pays for multi-vehicle support. The sample vehicle does not count towards
/// that: seeding a demo must not conjure a picker the owner did not need.
struct VehiclePickerBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // More than one vehicle the owner actually added, or the sample is
        // the one selected — otherwise there is nothing to switch between and
        // the control is a decoy.
        if let selected = model.selectedVehicle,
           model.snapshot.vehicles.filter { !$0.isDemo }.count > 1 || selected.isDemo {
            Menu {
                ForEach(model.snapshot.vehicles) { vehicle in
                    Button {
                        model.selectVehicle(vehicle.id)
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
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                }
            }
            .accessibilityLabel(Text("Selected vehicle: \(selected.displayName). Double tap to switch."))
            .accessibilityIdentifier("vehiclePicker")
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
