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
                                isSelected: model.isPinned(vehicle),
                                isHero: vehicles.count == 1
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            // Pinning is how somebody with several cars says
                            // which one the dashboard is about. With one car
                            // there is nothing to pin, so it is not offered.
                            if model.hasVehicleChoice {
                                Button {
                                    model.togglePin(vehicle)
                                } label: {
                                    Label(
                                        model.isPinned(vehicle) ? "Unpin from the dashboard" : "Pin to the dashboard",
                                        systemImage: model.isPinned(vehicle) ? "pin.slash" : "pin"
                                    )
                                }
                                .accessibilityIdentifier("garage.pin")
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
                        .cardSurface()
                    }
                    .accessibilityIdentifier("garage.addVehicle")

                    if let allowance = model.vehicleAllowanceNotice {
                        QuietNote(text: allowance)
                            .padding(.horizontal, Theme.Spacing.tight)
                    }
                }
                .padding(Theme.Spacing.large)
            }
            .background(LuminousField(strength: 0.6))
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
