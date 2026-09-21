import SwiftUI
import OdomindCore

/// Garage: the vehicles, and nothing else.
///
/// Build 1's Garage was small table rows under a bank icon, with Settings,
/// About and data-source links filling the rest of the screen — an admin
/// section wearing a garage's name. Everything global moved to Settings, under
/// the gear on Calendar. What is left is the cars.
struct GarageView: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationRouter.self) private var router

    @State private var showingAddVehicle = false

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.garagePath) {
            ScrollView {
                LazyVStack(spacing: Theme.Spacing.large) {
                    ForEach(vehicles) { vehicle in
                        Button {
                            router.garagePath.append(VehicleRoute.vehicle(vehicle.id))
                        } label: {
                            GarageVehicleCard(
                                vehicle: vehicle,
                                isSelected: vehicle.id == model.selectedVehicleID,
                                isHero: vehicles.count == 1
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if vehicle.id != model.selectedVehicleID {
                                Button {
                                    model.selectVehicle(vehicle.id)
                                } label: {
                                    Label("Use this vehicle", systemImage: "checkmark")
                                }
                            }
                            Button {
                                router.garagePath.append(VehicleRoute.artwork(vehicle.id))
                            } label: {
                                Label("Change the picture", systemImage: "photo")
                            }
                        }
                    }

                    Button {
                        addVehicle()
                    } label: {
                        HStack(spacing: Theme.Spacing.small) {
                            Image(systemName: "plus.circle.fill")
                            Text("Add a vehicle")
                        }
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.Palette.accent)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 56)
                        .background(Theme.Palette.raised, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                    }
                    .accessibilityIdentifier("garage.addVehicle")

                    if let allowance = model.vehicleAllowanceNotice {
                        QuietNote(text: allowance)
                            .padding(.horizontal, Theme.Spacing.tight)
                    }
                }
                .padding(Theme.Spacing.large)
            }
            .background(Theme.Palette.page)
            .navigationTitle("Garage")
            .odomindDestinations()
            .sheet(isPresented: $showingAddVehicle) {
                AddVehicleFlow()
            }
        }
    }

    /// The owner's vehicles, with the sample last so it never leads.
    private var vehicles: [Vehicle] {
        model.snapshot.vehicles.sorted { left, right in
            if left.isDemo != right.isDemo { return !left.isDemo }
            return left.sortIndex < right.sortIndex
        }
    }

    private func addVehicle() {
        if model.canAddVehicle {
            showingAddVehicle = true
        } else {
            router.presentPaywall = true
        }
    }
}
