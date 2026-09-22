import SwiftUI
import UIKit
import OdomindCore

/// The vehicle, presented the way a showroom presents one: cut out, lit from
/// above, floating on a soft shadow, with nothing framing it.
///
/// Build 3 drew the car on a grey plate inside a white card inside a grouped
/// background — three nested frames around one vehicle. There is no plate here.
/// The picture sits directly on the card and the only thing under it is its own
/// shadow, which is what makes a cut-out read as an object rather than a sticker.
///
/// What it shows, in order: the owner's own photo; a licensed studio image, the
/// moment there is a licence for one; a photograph Odomind is allowed to show,
/// with its credit; otherwise Odomind's own drawing. **Every vehicle gets
/// something** — the bottom of the ladder always has an answer.
struct StudioVehicleImage: View {
    @Environment(AppModel.self) private var model
    let vehicle: Vehicle
    /// The drawn width. The shadow and the lift scale with it.
    var width: CGFloat = 220

    @State private var ownPhoto: UIImage?

    private var height: CGFloat { width * 0.54 }

    var body: some View {
        let resolution = VehicleArtworkLoader.resolution(for: vehicle, model: model)
        ZStack(alignment: .bottom) {
            shadow
            picture(resolution)
                .frame(width: width, height: height)
        }
        .frame(width: width, height: height + 10)
        .task(id: VehiclePhotoService.revision(for: vehicle)) {
            model.photos.resolve(for: vehicle)
        }
        .task(id: vehicle.photoAttachmentID) {
            guard let id = vehicle.photoAttachmentID, let data = model.attachmentData(id) else {
                ownPhoto = nil
                return
            }
            ownPhoto = await Task.detached(priority: .userInitiated) { UIImage(data: data) }.value
        }
    }

    /// A soft ellipse, not a drop shadow on the artwork itself: a cut-out
    /// casts onto the ground it is standing on, and the ground here is the card.
    private var shadow: some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: [Color.black.opacity(0.17), Color.black.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: width * 0.34
                )
            )
            .frame(width: width * 0.86, height: width * 0.1)
            .offset(y: 2)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func picture(_ resolution: VehicleArtworkResolution) -> some View {
        if let ownPhoto {
            cutout(Image(uiImage: ownPhoto))
        } else if case .found(let found) = model.photos.status(for: vehicle.id) {
            CreditedVehiclePhoto(photo: found, width: width, height: height)
        } else {
            VehicleArtworkView(
                resolution: resolution,
                paint: (vehicle.artwork ?? .default).paintColor,
                accessibilityText: "\(vehicle.displayName). \(resolution.disclosure)"
            )
        }
    }

    private func cutout(_ image: Image) -> some View {
        image
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
            .accessibilityLabel(Text("\(vehicle.displayName). Your photo."))
    }
}

/// A photograph Odomind is allowed to show, with the credit its licence
/// requires attached to it.
///
/// Sized and clipped *before* the credit goes on. `aspectRatio(.fill)` reports
/// a layout size that covers the proposal rather than fitting inside it, so a
/// landscape photograph in a short frame lays out taller than the frame — and
/// a bottom-trailing credit on the image itself falls outside and is clipped
/// away. The first real photograph Odomind ever showed went out with nothing
/// naming its author because of exactly that.
struct CreditedVehiclePhoto: View {
    let photo: VehiclePhoto
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        AsyncImage(url: photo.imageURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
                    .accessibilityIdentifier("vehicle.photo")
                    .overlay(alignment: .bottomTrailing) { credit }
            case .failure:
                Color.clear
            default:
                ProgressView().controlSize(.small)
            }
        }
        .frame(width: width, height: height)
        .accessibilityLabel(Text("Photograph. Photo by \(photo.creditLine)"))
    }

    private var credit: some View {
        Text(photo.creditLine)
            .font(.system(size: 9))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.black.opacity(0.55), in: Capsule())
            .padding(5)
            .accessibilityHidden(true)
    }
}
