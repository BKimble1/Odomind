import SwiftUI
import UIKit
import OdomindCore

struct VehicleDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let vehicleID: UUID

    @State private var nickname = ""
    @State private var showingDeleteConfirmation = false
    @State private var didLoad = false

    private var vehicle: Vehicle? { model.snapshot.vehicle(id: vehicleID) }

    var body: some View {
        Group {
            if let vehicle {
                content(vehicle)
            } else {
                ContentUnavailableView(
                    "Vehicle not found",
                    systemImage: "car.side",
                    description: Text("This vehicle may have been removed.")
                )
            }
        }
        .navigationTitle(vehicle?.displayName ?? "Vehicle")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func content(_ vehicle: Vehicle) -> some View {
        List {
            Section {
                StudioVehicleImage(vehicle: vehicle, width: 250)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.small)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            .listSectionSeparator(.hidden)

            if model.hasVehicleChoice {
                Section {
                    Toggle("Show on the dashboard", isOn: pinBinding(vehicle))
                        .accessibilityIdentifier("vehicle.pin")
                }
            }

            Section {
                NavigationLink(value: VehicleRoute.artwork(vehicleID)) {
                    Label("Change the picture", systemImage: "photo")
                }
                .accessibilityIdentifier("vehicle.artwork")
            } footer: {
                Text(VehicleArtworkResolver.resolve(
                    vehicle: vehicle,
                    hasPhoto: vehicle.photoAttachmentID.flatMap { model.snapshot.attachment(id: $0) } != nil
                ).disclosure)
            }

            Section("Name") {
                TextField("Nickname", text: $nickname)
                    .onSubmit { saveNickname(vehicle) }
            }


            Section("Identity") {
                ValueRow(label: "Year", value: vehicle.identity.modelYear.map(String.init) ?? "Not set")
                ValueRow(label: "Make", value: vehicle.identity.make)
                ValueRow(label: "Model", value: vehicle.identity.model)
                if let trim = vehicle.identity.trim, !trim.isEmpty {
                    ValueRow(label: "Trim", value: trim)
                }
                if let body = vehicle.identity.bodyClass, !body.isEmpty {
                    ValueRow(label: "Body", value: body)
                }
                if let suffix = vehicle.identity.vinSuffix {
                    ValueRow(
                        label: "VIN",
                        value: "…\(suffix)",
                        secondary: "Stored on this device only"
                    )
                }
            }

            Section {
                NavigationLink(value: VehicleRoute.configuration(vehicleID)) {
                    Label("Configuration", systemImage: "gearshape.2")
                }
                NavigationLink(value: VehicleRoute.specifications(vehicleID)) {
                    Label("Specifications", systemImage: "list.bullet.rectangle")
                }
                .accessibilityIdentifier("vehicle.specifications")
                NavigationLink(value: VehicleRoute.odometerHistory(vehicleID)) {
                    Label("Odometer history", systemImage: "gauge.with.dots.needle.33percent")
                }
                NavigationLink(value: VehicleRoute.spending(vehicleID)) {
                    Label("Spending", systemImage: "chart.bar.xaxis")
                }
                .accessibilityIdentifier("vehicle.spending")
            }

            if !vehicle.configuration.openQuestions.isEmpty {
                Section {
                    ForEach(vehicle.configuration.openQuestions, id: \.self) { question in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(question.prompt)
                                .font(.callout.weight(.medium))
                            Text(question.rationale)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    NavigationLink(value: VehicleRoute.configuration(vehicleID)) {
                        Text("Answer these")
                    }
                } header: {
                    Label("Still to confirm", systemImage: "questionmark.circle")
                } footer: {
                    Text("Odomind leaves the jobs that depend on these out of your plan rather than guessing.")
                }
            }

            Section("Units and dates") {
                Picker("Distance unit", selection: unitBinding(vehicle)) {
                    Text("Miles").tag(DistanceUnit.miles)
                    Text("Kilometers").tag(DistanceUnit.kilometers)
                }
                DatePicker(
                    "Entered service",
                    selection: inServiceBinding(vehicle),
                    in: ...Date(),
                    displayedComponents: .date
                )
                Text("When it first went on the road — not when you bought it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Button("Remove this vehicle", role: .destructive) {
                    showingDeleteConfirmation = true
                }
            } footer: {
                Text("Deletes its mileage, jobs, history and receipts. Other vehicles are untouched.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(LuminousField(strength: 0.5))
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            nickname = vehicle.nickname ?? ""
        }
        .onDisappear { saveNickname(vehicle) }
        .confirmationDialog("Remove this vehicle?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Remove and delete its records", role: .destructive) {
                Task {
                    await model.deleteVehicle(id: vehicleID)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Everything recorded for \(vehicle.displayName) is deleted, including receipts. This cannot be undone. Export a backup first if you want to keep it.")
        }
    }



    /// The dashboard's car, as a switch on the car itself. Pinning lives in
    /// the garage's context menu too; this is the same one thing, where
    /// somebody looking at a vehicle would expect to find it.
    private func pinBinding(_ vehicle: Vehicle) -> Binding<Bool> {
        Binding(
            get: { model.isPinned(vehicle) },
            set: { _ in model.togglePin(vehicle) }
        )
    }

    private func saveNickname(_ vehicle: Vehicle) {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != (vehicle.nickname ?? "") else { return }
        var copy = vehicle
        copy.nickname = trimmed.isEmpty ? nil : trimmed
        model.updateVehicle(copy)
    }

    private func unitBinding(_ vehicle: Vehicle) -> Binding<DistanceUnit> {
        Binding(
            get: { vehicle.displayUnit },
            set: { newValue in
                var copy = vehicle
                copy.displayUnit = newValue
                model.updateVehicle(copy)
            }
        )
    }

    private func inServiceBinding(_ vehicle: Vehicle) -> Binding<Date> {
        Binding(
            get: { vehicle.inServiceOn ?? defaultInServiceDate(vehicle) },
            set: { newValue in
                var copy = vehicle
                copy.inServiceOn = newValue
                model.updateVehicle(copy)
            }
        )
    }

    /// A sensible starting point for the picker, derived from the model year.
    /// Never written until the owner actually picks a date.
    private func defaultInServiceDate(_ vehicle: Vehicle) -> Date {
        guard let year = vehicle.identity.modelYear else { return Date() }
        var components = DateComponents()
        components.year = year
        components.month = 1
        components.day = 1
        return model.calendar.date(from: components) ?? Date()
    }
}

/// The full list of dated readings, with corrections and the replacement log.
struct OdometerHistoryView: View {
    @Environment(AppModel.self) private var model
    let vehicleID: UUID

    @State private var showingReplacement = false

    private var vehicle: Vehicle? { model.snapshot.vehicle(id: vehicleID) }

    var body: some View {
        List {
            if let vehicle {
                let readings = model.snapshot.readings(for: vehicleID).sorted { $0.recordedOn > $1.recordedOn }
                let ledger = model.ledger(for: vehicle)

                if readings.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No readings yet",
                            systemImage: "gauge.with.dots.needle.33percent",
                            description: Text("Add your current mileage from the Today screen.")
                        )
                    }
                }

                if !vehicle.odometerReplacements.isEmpty {
                    Section {
                        ForEach(vehicle.odometerReplacements) { replacement in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Format.date(replacement.occurredOn))
                                Text("\(Format.distance(replacement.previousUnitFinalReading)) → \(Format.distance(replacement.replacementUnitStartReading)), carrying \(Format.distance(replacement.offset)) forward")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let note = replacement.note {
                                    Text(note).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .swipeActions {
                                Button("Remove", role: .destructive) {
                                    model.removeOdometerReplacement(vehicleID: vehicleID, replacementID: replacement.id)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    } header: {
                        Text("Odometer replacements")
                    } footer: {
                        Text("Odomind adds this distance to every reading taken afterwards, so your schedules keep counting from where the old unit stopped.")
                    }
                }

                Section {
                    ForEach(readings) { reading in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(Format.distance(reading.value))
                                    .monospacedDigit()
                                Spacer()
                                Text(Format.date(reading.recordedOn))
                                    .foregroundStyle(.secondary)
                            }
                            let cumulative = ledger.cumulative(reading)
                            if cumulative != reading.value {
                                Text("\(Format.distance(cumulative)) total distance")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(reading.source.displayName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if let note = reading.note {
                                Text(note).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .swipeActions {
                            Button("Delete", role: .destructive) {
                                model.deleteReading(id: reading.id)
                            }
                        }
                    }
                } header: {
                    Text("Readings")
                } footer: {
                    Text("Deleting a reading recalculates every schedule that used it.")
                }

                Section {
                    Button("Record an odometer replacement") { showingReplacement = true }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Odometer history")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingReplacement) {
            if let vehicle {
                OdometerReplacementSheet(vehicle: vehicle)
            }
        }
    }
}
