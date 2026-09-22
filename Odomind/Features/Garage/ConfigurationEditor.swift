import SwiftUI
import OdomindCore

/// Confirms what the vehicle actually is.
///
/// These answers decide which tasks appear. Every field can be left
/// unconfirmed, and leaving one unconfirmed is a real outcome: the tasks that
/// depend on it stay out of the plan rather than being guessed either way.
struct ConfigurationEditor: View {
    @Environment(AppModel.self) private var model
    let vehicleID: UUID

    private var vehicle: Vehicle? { model.snapshot.vehicle(id: vehicleID) }

    var body: some View {
        Group {
            if let vehicle {
                content(vehicle)
            } else {
                ContentUnavailableView("Vehicle not found", systemImage: "car.side")
            }
        }
        .navigationTitle("Configuration")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func content(_ vehicle: Vehicle) -> some View {
        List {
            Section {
                Picker("Runs on", selection: binding(vehicle, \.powertrain)) {
                    ForEach(PowertrainKind.allCases, id: \.self) { value in
                        Text(value.displayName).tag(value)
                    }
                }
            } footer: {
                Text(ConfigurationQuestion.powertrain.rationale)
            }

            Section {
                Picker("Transmission", selection: binding(vehicle, \.transmission)) {
                    ForEach(TransmissionKind.allCases, id: \.self) { value in
                        Text(value.displayName).tag(value)
                    }
                }
                Stepper(
                    vehicle.configuration.transmissionSpeeds.map { "\($0) speeds" } ?? "Speeds not set",
                    value: Binding(
                        get: { vehicle.configuration.transmissionSpeeds ?? 0 },
                        set: { newValue in
                            update(vehicle) { $0.transmissionSpeeds = newValue == 0 ? nil : newValue }
                        }
                    ),
                    in: 0...12
                )
            } footer: {
                Text(ConfigurationQuestion.transmission.rationale)
            }

            Section {
                Picker("Drivetrain", selection: binding(vehicle, \.drivetrain)) {
                    ForEach(DrivetrainLayout.allCases, id: \.self) { value in
                        Text(value.displayName).tag(value)
                    }
                }
                Picker("Transfer case", selection: binding(vehicle, \.transferCase)) {
                    ForEach(Fitment.allCases, id: \.self) { value in
                        Text(value.displayName).tag(value)
                    }
                }
            } header: {
                Text("Drivetrain")
            } footer: {
                Text("Decides whether differential and transfer-case service appear.")
            }

            Section {
                Picker("Camshaft drive", selection: binding(vehicle, \.camshaftDrive)) {
                    ForEach(CamshaftDrive.allCases, id: \.self) { value in
                        Text(value.displayName).tag(value)
                    }
                }
            } header: {
                Text("Engine")
            } footer: {
                Text(ConfigurationQuestion.camshaftDrive.rationale)
            }

            Section {
                HStack {
                    Text("Engine size")
                    Spacer()
                    TextField(
                        "e.g. 3.8",
                        text: Binding(
                            get: { vehicle.configuration.engineDisplacementLiters.map { String($0) } ?? "" },
                            set: { newValue in
                                update(vehicle) { $0.engineDisplacementLiters = Double(newValue) }
                            }
                        )
                    )
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                    Text("L").foregroundStyle(.secondary)
                }
                HStack {
                    Text("Engine code")
                    Spacer()
                    TextField(
                        "optional",
                        text: Binding(
                            get: { vehicle.configuration.engineCode ?? "" },
                            set: { newValue in
                                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                update(vehicle) { $0.engineCode = trimmed.isEmpty ? nil : trimmed }
                            }
                        )
                    )
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                }
            }

            Section {
                Picker("Market", selection: binding(vehicle, \.market)) {
                    ForEach(Market.allCases, id: \.self) { value in
                        Text(value.displayName).tag(value)
                    }
                }
                Picker("Use", selection: binding(vehicle, \.usageProfile)) {
                    ForEach(UsageProfile.allCases, id: \.self) { value in
                        Text(value.displayName).tag(value)
                    }
                }
            } header: {
                Text("Where and how it is driven")
            } footer: {
                Text("Offered only where one is published for your vehicle. Unset changes nothing.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(LuminousField(strength: 0.5))
    }

    private func binding<Value>(
        _ vehicle: Vehicle,
        _ keyPath: WritableKeyPath<VehicleConfiguration, Value>
    ) -> Binding<Value> {
        Binding(
            get: { vehicle.configuration[keyPath: keyPath] },
            set: { newValue in
                update(vehicle) { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    private func update(_ vehicle: Vehicle, _ change: (inout VehicleConfiguration) -> Void) {
        var copy = vehicle
        change(&copy.configuration)
        model.updateVehicle(copy)
    }
}
