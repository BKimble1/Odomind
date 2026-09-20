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
                    TodayView()
                        .tabItem {
                            Label(
                                NavigationRouter.Tab.today.title,
                                systemImage: NavigationRouter.Tab.today.symbolName
                            )
                        }
                        .tag(NavigationRouter.Tab.today)

                    MaintenanceView()
                        .tabItem {
                            Label(
                                NavigationRouter.Tab.maintenance.title,
                                systemImage: NavigationRouter.Tab.maintenance.symbolName
                            )
                        }
                        .tag(NavigationRouter.Tab.maintenance)

                    GarageView()
                        .tabItem {
                            Label(
                                NavigationRouter.Tab.garage.title,
                                systemImage: NavigationRouter.Tab.garage.symbolName
                            )
                        }
                        .tag(NavigationRouter.Tab.garage)

                    HistoryView()
                        .tabItem {
                            Label(
                                NavigationRouter.Tab.history.title,
                                systemImage: NavigationRouter.Tab.history.symbolName
                            )
                        }
                        .tag(NavigationRouter.Tab.history)
                }
            }
        }
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
        .onChange(of: router.pendingVehicleSelection) { _, newValue in
            guard let newValue, model.snapshot.vehicle(id: newValue) != nil else { return }
            model.selectVehicle(newValue)
            router.pendingVehicleSelection = nil
        }
    }
}

/// The picker used at the top of Today, Maintenance and History.
///
/// Hidden entirely when there is one vehicle, so single-vehicle use never pays
/// for multi-vehicle support.
struct VehiclePickerBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.snapshot.vehicles.count > 1, let selected = model.selectedVehicle {
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
