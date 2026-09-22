import SwiftUI
import UIKit
import OdomindCore

/// Loads a vehicle's photo once and hands back the artwork decision.
///
/// The resolver is pure and lives in the core; this is the part that has to
/// touch the attachment store, so it is kept in one place rather than repeated
/// in every card.
@MainActor
struct VehicleArtworkLoader {
    static func resolution(for vehicle: Vehicle, model: AppModel) -> VehicleArtworkResolution {
        VehicleArtworkResolver.resolve(
            vehicle: vehicle,
            hasPhoto: vehicle.photoAttachmentID.flatMap { model.snapshot.attachment(id: $0) } != nil
        )
    }
}

/// The vehicle illustration or photo, on its quiet ground.
///
/// A subtle floor, not a garage scene: the brief asked for something
/// editorially clean rather than a diorama.
struct VehiclePortrait: View {
    @Environment(AppModel.self) private var model
    let vehicle: Vehicle
    var height: CGFloat = 132
    var cornerRadius: CGFloat = Theme.Radius.card

    @State private var photo: UIImage?

    /// The owner's own picture beats everything. Then a real photograph
    /// Odomind is allowed to show. The drawing is what is left when neither
    /// exists — an exception now, not the normal experience.
    private var resolvedPhoto: VehiclePhoto? {
        guard photo == nil else { return nil }
        guard case .found(let found) = model.photos.status(for: vehicle.id) else { return nil }
        return found
    }

    var body: some View {
        let resolution = VehicleArtworkLoader.resolution(for: vehicle, model: model)
        Group {
            if let found = resolvedPhoto {
                RemoteVehiclePhoto(photo: found, height: height)
                    .accessibilityLabel(
                        Text("\(vehicle.displayName). \(found.matchLevel.disclosure). Photo by \(found.creditLine)")
                    )
            } else {
                VehicleArtworkView(
                    resolution: resolution,
                    paint: (vehicle.artwork ?? .default).paintColor,
                    photo: photo,
                    accessibilityText: "\(vehicle.displayName). \(resolution.disclosure)"
                )
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .background(Theme.Palette.artworkGround)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: VehiclePhotoService.revision(for: vehicle)) {
            model.photos.resolve(for: vehicle)
        }
        .task(id: vehicle.photoAttachmentID) {
            // Decoding is not free and has no business on the main actor's
            // critical path, so it happens off it and the result comes back.
            guard let id = vehicle.photoAttachmentID, let data = model.attachmentData(id) else {
                photo = nil
                return
            }
            photo = await Task.detached(priority: .userInitiated) { UIImage(data: data) }.value
        }
    }
}

/// A vehicle in the garage: a picture worth looking at, a name, the mileage,
/// and one line about what is coming.
struct GarageVehicleCard: View {
    @Environment(AppModel.self) private var model
    let vehicle: Vehicle
    let isSelected: Bool
    var isHero: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Flush to the card's own edges and square at the bottom, so the
            // picture *is* the top of the card. Build 2 drew a rounded grey
            // plate inside a rounded white card inside a grouped background —
            // three nested frames around one photograph.
            VehiclePortrait(
                vehicle: vehicle,
                height: isHero ? 168 : 124,
                cornerRadius: 0
            )
            .clipShape(
                .rect(
                    topLeadingRadius: Theme.Radius.card,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: Theme.Radius.card
                )
            )

            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.small) {
                    Text(vehicle.displayName)
                        .font(isHero ? .title3.weight(.semibold) : .headline)
                        .foregroundStyle(Theme.Palette.primaryText)
                    if vehicle.isDemo { SampleBadge() }
                    Spacer(minLength: Theme.Spacing.small)
                    if isSelected {
                        // Never colour alone: the word is the signal and the
                        // dot is decoration.
                        Label("Selected", systemImage: "checkmark.circle.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.Palette.accent)
                            // Keeps its width against a long vehicle name;
                            // the name is the one that should wrap, and a
                            // truncated "Selec…" is what the audit saw.
                            .fixedSize()
                    }
                }

                if vehicle.displayName != vehicle.identity.displayName {
                    Text(vehicle.identity.displayName)
                        .font(.subheadline)
                        .foregroundStyle(Theme.Palette.secondaryText)
                }

                Text(statusLine)
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Theme.Spacing.medium)
        }
        .background(Theme.Palette.raised, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("garage.vehicle")
    }

    /// Mileage and the single most useful thing about the plan — never a
    /// health score, and never an all-clear when history is unknown.
    private var statusLine: String {
        var parts: [String] = []
        if let reading = model.latestReading(for: vehicle.id) {
            parts.append(Format.distance(reading.value))
        } else {
            parts.append("No mileage yet")
        }

        let evaluations = model.evaluations(for: vehicle.id)
        let overdue = evaluations.filter { $0.state == .overdue }.count
        let dueSoon = evaluations.filter { $0.state == .dueSoon }.count
        let unknown = evaluations.filter { $0.state == .historyUnknown || $0.state == .needsSetup }.count

        if overdue > 0 {
            parts.append("\(overdue) overdue")
        } else if dueSoon > 0 {
            parts.append("\(dueSoon) due soon")
        } else if evaluations.contains(where: { $0.state.isScheduled }) {
            parts.append("nothing due")
        } else if unknown > 0 {
            parts.append("plan not started")
        }
        return parts.joined(separator: " · ")
    }
}

/// A photograph fetched from a provider, with the credit its licence
/// requires.
///
/// `AsyncImage` rather than a hand-rolled loader: it already shares
/// `URLCache`, cancels with the view, and decodes off the main thread. The
/// image comes back at a display width the provider rendered, so nothing here
/// is downsampling a twenty-megapixel original on the way past.
struct RemoteVehiclePhoto: View {
    let photo: VehiclePhoto
    var height: CGFloat

    var body: some View {
        AsyncImage(url: photo.imageURL) { phase in
            switch phase {
            case .success(let image):
                // Sized and clipped *here*, before the credit goes on.
                //
                // `aspectRatio(contentMode: .fill)` reports a layout size that
                // covers the proposal rather than fitting inside it: a
                // landscape photograph in a 124-point card lays out more than
                // twice as tall as the card. A bottom-trailing overlay on the
                // image therefore sat below the card's bottom edge, and the
                // `.clipped()` further out removed it — so the first real
                // photograph Odomind ever showed went out with nothing naming
                // its author. The licence is a condition of showing the
                // picture, so that is not a cosmetic bug.
                //
                // Caught by a screenshot and then by the assertion written
                // from it, not by anything that existed before.
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: height)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    // Present only when a photograph has actually been
                    // fetched and drawn, so a capture run can tell a real
                    // photo from the drawing that stands in for one.
                    .accessibilityIdentifier("vehicle.photo")
                    .overlay(alignment: .bottomTrailing) {
                        Text(photo.creditLine)
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.55), in: Capsule())
                            .padding(6)
                            .accessibilityLabel(Text("Photo by \(photo.creditLine)"))
                    }
            case .failure:
                // A provider having a bad afternoon is not worth an error
                // card on the garage screen.
                Color.clear
            default:
                ProgressView().controlSize(.small)
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipped()
    }
}
