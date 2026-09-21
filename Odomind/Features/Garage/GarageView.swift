import SwiftUI
import UIKit
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
    @Environment(AppModel.self) private var model

    let vehicle: Vehicle
    let isSelected: Bool

    @State private var photo: UIImage?

    var body: some View {
        HStack(spacing: Theme.Spacing.medium) {
            marque
            VStack(alignment: .leading, spacing: 1) {
                Text(vehicle.displayName)
                Text(vehicle.identity.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if vehicle.isDemo {
                SampleBadge()
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
        .task(id: vehicle.photoAttachmentID) {
            photo = vehicle.photoAttachmentID
                .flatMap { model.attachmentData($0) }
                .flatMap { UIImage(data: $0) }
        }
    }

    /// The owner's photo where there is one, the generic symbol otherwise.
    ///
    /// Same slot and same width either way, so a garage where only some
    /// vehicles have a picture does not come out ragged. Hidden from
    /// VoiceOver in both cases: the row is combined and already says the
    /// vehicle's name, and a decorative image that repeats it is noise.
    @ViewBuilder
    private var marque: some View {
        if let photo {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.badge))
                .accessibilityHidden(true)
        } else {
            Image(systemName: "car.side")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)
                .accessibilityHidden(true)
        }
    }
}
