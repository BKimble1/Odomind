import SwiftUI
import PhotosUI
import OdomindCore

/// How this vehicle is pictured.
///
/// Switching to an illustration never deletes the owner's photo: the photo
/// stays attached and switching back shows it again. That matters because the
/// screenshots showed a real vehicle whose "photo" was a phone screenshot —
/// the right answer there is a better display choice, not deleting what
/// somebody saved.
struct VehicleArtworkPicker: View {
    @Environment(AppModel.self) private var model
    let vehicleID: UUID

    @State private var photoItem: PhotosPickerItem?
    @State private var isImporting = false

    var body: some View {
        Group {
            if let vehicle = model.snapshot.vehicle(id: vehicleID) {
                content(for: vehicle)
            } else {
                ContentUnavailableView("Vehicle not found", systemImage: "car.side")
            }
        }
        .navigationTitle("Picture")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func content(for vehicle: Vehicle) -> some View {
        let artwork = vehicle.artwork ?? .default
        let resolution = VehicleArtworkLoader.resolution(for: vehicle, model: model)

        List {
            Section {
                VehiclePortrait(vehicle: vehicle, height: 150)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            } footer: {
                // The fallback distinction lives here, on the screen about the
                // picture, rather than on every card.
                Text(resolution.disclosure)
            }

            Section("Show") {
                Picker("Show", selection: Binding(
                    get: { artwork.mode },
                    set: { newValue in update(vehicle) { $0.mode = newValue } }
                )) {
                    ForEach(VehicleArtworkMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("artwork.mode")

                if artwork.mode == .photo {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label(
                            vehicle.photoAttachmentID == nil ? "Choose a photo" : "Replace the photo",
                            systemImage: "photo"
                        )
                    }
                    .accessibilityIdentifier("artwork.choosePhoto")
                    if vehicle.photoAttachmentID != nil {
                        Button("Remove the photo", role: .destructive) {
                            model.setPhoto(nil, for: vehicle)
                        }
                    }
                    if vehicle.photoAttachmentID == nil {
                        QuietNote(text: "No photo saved yet, so Odomind is showing the illustration.")
                    }
                }
            }

            if artwork.mode == .illustration {
                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: Theme.Spacing.medium) {
                        ForEach(VehiclePaintColor.allCases, id: \.self) { paint in
                            Button {
                                update(vehicle) { $0.paintColor = paint }
                            } label: {
                                Circle()
                                    .fill(VehiclePaintTones.tones(for: paint).body)
                                    .frame(width: 34, height: 34)
                                    .overlay {
                                        Circle().strokeBorder(
                                            artwork.paintColor == paint
                                                ? Theme.Palette.accent : Theme.Palette.separator,
                                            lineWidth: artwork.paintColor == paint ? 3 : 1
                                        )
                                    }
                                    .frame(width: Theme.minimumTapTarget, height: Theme.minimumTapTarget)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(paint.displayName))
                            .accessibilityAddTraits(artwork.paintColor == paint ? [.isButton, .isSelected] : .isButton)
                            .accessibilityIdentifier("artwork.paint.\(paint.rawValue)")
                        }
                    }
                } header: {
                    Text("Colour")
                }

                Section {
                    Picker("Body style", selection: Binding(
                        get: { artwork.bodyStyleOverride },
                        set: { newValue in update(vehicle) { $0.bodyStyleOverride = newValue } }
                    )) {
                        Text("Work it out for me").tag(VehicleBodyStyle?.none)
                        ForEach(VehicleBodyStyle.allCases, id: \.self) { style in
                            Text(style.displayName).tag(VehicleBodyStyle?.some(style))
                        }
                    }
                    .accessibilityIdentifier("artwork.bodyStyle")
                } footer: {
                    Text("Odomind guesses the shape from what the vehicle lookup reported. Set it yourself if the picture looks wrong. This changes the drawing only — it has no effect on your maintenance or on which parts fit.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .task(id: photoItem) {
            guard let photoItem else { return }
            isImporting = true
            defer { isImporting = false }
            // Loading and re-encoding happens off the main actor; only the
            // store write comes back to it.
            guard let data = try? await photoItem.loadTransferable(type: Data.self) else { return }
            let prepared = ImageProcessing.prepare(data: data, contentType: "image/jpeg")
            if let id = model.addAttachment(data: prepared.data, contentType: prepared.contentType) {
                model.setPhoto(id, for: vehicle)
            }
            self.photoItem = nil
        }
    }

    private func update(_ vehicle: Vehicle, _ change: (inout VehicleArtworkPreference) -> Void) {
        var artwork = vehicle.artwork ?? .default
        change(&artwork)
        model.setArtwork(artwork, for: vehicle.id)
    }
}
