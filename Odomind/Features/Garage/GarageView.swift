import SwiftUI
import OdomindCore

struct GarageView: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationRouter.self) private var router

    @State private var showingAddVehicle = false

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.garagePath) {
            List {
                Section {
                    ForEach(model.snapshot.vehicles) { vehicle in
                        NavigationLink(value: GarageRoute.vehicle(vehicle.id)) {
                            VehicleRow(vehicle: vehicle, isSelected: vehicle.id == model.selectedVehicleID)
                        }
                        .swipeActions(edge: .leading) {
                            if vehicle.id != model.selectedVehicleID {
                                Button {
                                    model.selectVehicle(vehicle.id)
                                } label: {
                                    Label("Select", systemImage: "checkmark")
                                }
                                .tint(.accentColor)
                            }
                        }
                    }
                    Button {
                        showingAddVehicle = true
                    } label: {
                        Label("Add a vehicle", systemImage: "plus")
                    }
                } header: {
                    Text("Vehicles")
                }

                Section {
                    NavigationLink(value: GarageRoute.settings) {
                        Label("Settings", systemImage: "gearshape")
                    }
                    NavigationLink(value: GarageRoute.dataSources) {
                        Label("Where the data comes from", systemImage: "doc.text.magnifyingglass")
                    }
                    NavigationLink(value: GarageRoute.about) {
                        Label("About Odomind", systemImage: "info.circle")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Garage")
            .navigationDestination(for: GarageRoute.self) { route in
                switch route {
                case .vehicle(let id):
                    VehicleDetailView(vehicleID: id)
                case .specifications(let id):
                    SpecificationsView(vehicleID: id)
                case .configuration(let id):
                    ConfigurationEditor(vehicleID: id)
                case .odometerHistory(let id):
                    OdometerHistoryView(vehicleID: id)
                case .settings:
                    SettingsView()
                case .reminders:
                    ReminderSettingsView()
                case .dataSources:
                    DataSourcesView()
                case .backup:
                    BackupView()
                case .about:
                    AboutView()
                case .privacy:
                    PrivacyView()
                case .diagnostics:
                    DiagnosticsView()
                }
            }
            .sheet(isPresented: $showingAddVehicle) {
                AddVehicleFlow()
            }
        }
    }
}

struct VehicleRow: View {
    let vehicle: Vehicle
    let isSelected: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.medium) {
            Image(systemName: "car.side")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(vehicle.displayName)
                Text(vehicle.identity.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if vehicle.isDemo {
                Text("SAMPLE")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.orange)
            }
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityLabel(Text("Currently selected"))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("garage.vehicle")
    }
}
