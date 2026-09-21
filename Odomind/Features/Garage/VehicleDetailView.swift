import SwiftUI
import PhotosUI
import UIKit
import OdomindCore

struct VehicleDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let vehicleID: UUID

    @State private var nickname = ""
    @State private var showingDeleteConfirmation = false
    @State private var didLoad = false
    @State private var photoItem: PhotosPickerItem?
    @State private var photo: UIImage?

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
            Section("Name") {
                TextField("Nickname", text: $nickname)
                    .onSubmit { saveNickname(vehicle) }
                Text("A nickname shows instead of the year, make and model.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            photoSection(vehicle)

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
                NavigationLink(value: GarageRoute.configuration(vehicleID)) {
                    Label("Configuration", systemImage: "gearshape.2")
                }
                NavigationLink(value: GarageRoute.specifications(vehicleID)) {
                    Label("Specifications", systemImage: "list.bullet.rectangle")
                }
                .accessibilityIdentifier("vehicle.specifications")
                NavigationLink(value: GarageRoute.odometerHistory(vehicleID)) {
                    Label("Odometer history", systemImage: "gauge.with.dots.needle.33percent")
                }
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
                    NavigationLink(value: GarageRoute.configuration(vehicleID)) {
                        Text("Answer these")
                    }
                } header: {
                    Label("Still to confirm", systemImage: "questionmark.circle")
                } footer: {
                    Text("Until these are answered, Odomind leaves the tasks that depend on them out of your plan rather than guessing.")
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
                Text("The date the vehicle was first put on the road. Used for age-based manufacturer milestones. Different from when you bought it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Button("Remove this vehicle", role: .destructive) {
                    showingDeleteConfirmation = true
                }
            } footer: {
                Text("This deletes its mileage, tasks, service history, receipts and reminders. Other vehicles are untouched.")
            }
        }
        .listStyle(.insetGrouped)
        // Keyed on the identifier, so the picture reloads when the photo is
        // replaced or removed and is read from disk once rather than on every
        // pass through the body.
        .task(id: vehicle.photoAttachmentID) {
            photo = vehicle.photoAttachmentID
                .flatMap { model.attachmentData($0) }
                .flatMap { UIImage(data: $0) }
        }
        .onChange(of: photoItem) { _, newValue in
            guard let newValue else { return }
            Task { await attachPhoto(newValue, to: vehicle) }
        }
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

    /// A picture of the vehicle, which is decoration rather than a record.
    ///
    /// It earns its place by making a two-car garage readable at a glance, and
    /// it is held to the same rule as everything else here: on this device,
    /// inside the backup, nowhere else.
    @ViewBuilder
    private func photoSection(_ vehicle: Vehicle) -> some View {
        Section {
            if let photo {
                // A fixed-height container with the picture overlaid on it,
                // rather than a sized image: `scaledToFill` on a frame that
                // proposes the full width can overflow it, and this way the
                // row's height is decided before the image is drawn into it.
                Color.clear
                    .frame(height: 180)
                    .overlay {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                    }
                    .clipped()
                    .listRowInsets(EdgeInsets())
                    // A photo of a car says nothing a screen reader needs that
                    // the vehicle's own name does not already say, and Odomind
                    // will not describe an image it has not looked at.
                    .accessibilityHidden(true)
            }

            PhotosPicker(selection: $photoItem, matching: .images) {
                Label(
                    vehicle.photoAttachmentID == nil ? "Add a photo" : "Replace the photo",
                    systemImage: "camera"
                )
            }
            .accessibilityIdentifier("vehicle.photoPicker")

            if vehicle.photoAttachmentID != nil {
                Button("Remove the photo", role: .destructive) {
                    model.setPhoto(nil, for: vehicle)
                }
                .accessibilityIdentifier("vehicle.removePhoto")
            }
        } header: {
            Text("Photo")
        } footer: {
            Text("Stored on this device with your records and included in a backup. Odomind does not upload it and does not read anything from it.")
        }
    }

    private func attachPhoto(_ item: PhotosPickerItem, to vehicle: Vehicle) async {
        defer { photoItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            model.alert = AppAlert(
                title: "Could not read that photo",
                message: "Odomind could not load the image you picked.",
                recoverySuggestion: "Try a different photo, or take a new one."
            )
            return
        }
        guard let id = model.addAttachment(data: data, contentType: "image/jpeg") else { return }
        model.setPhoto(id, for: vehicle)
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
