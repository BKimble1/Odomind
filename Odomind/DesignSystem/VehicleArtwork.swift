import SwiftUI
import OdomindCore

/// Odomind's vehicle illustrations.
///
/// **Why side profile, not three-quarter.** What has to read correctly is the
/// body shape, the generation and the door count — a four-door Wrangler has to
/// look like a four-door Wrangler and not a generic sedan. Profile is where
/// those read most reliably, and where nine body styles can be drawn to one
/// consistent scale, ground line, wheel style and stroke weight. A
/// hand-authored three-quarter set would have been nine separate perspective
/// problems and would have come out less consistent, not more impressive.
///
/// **Why vector paths, not bundled images.** They scale to any size without a
/// blurry @2x, they recolour for the owner's paint choice without nine copies
/// per colour, they are legible in both appearances because every tone is a
/// semantic token, and they add nothing to the download. They also work
/// offline, which the garage has to.
///
/// Everything is drawn in one canonical 250 × 100 box and scaled to fit, so a
/// pickup and a coupe sit on the same ground line with the same wheels.
enum VehicleArt {
    /// The canonical drawing box. Every silhouette is authored in these units.
    static let boxSize = CGSize(width: 250, height: 100)
    static let aspectRatio = boxSize.width / boxSize.height

    static let groundY: CGFloat = 95
    static let wheelRadius: CGFloat = 18
    static let wheelCenterY: CGFloat = 95 - 18
    static let frontWheelX: CGFloat = 55
    static let rearWheelX: CGFloat = 195

    /// Wheels are wheels whatever colour the car is, so these are fixed
    /// rather than derived from the paint. That is what keeps the garage
    /// looking like one set of drawings.
    static let tyre = Color(uiColor: UIColor(hex: 0x24292B))
    static let rim = Color(uiColor: UIColor(hex: 0xB9C2C5))
    static let hub = Color(uiColor: UIColor(hex: 0x6E787B))

    /// A hairline around the tyre, and the one part of the wheel that does
    /// change with the appearance.
    ///
    /// In dark mode the artwork panel is near-black and so is a tyre, which
    /// measured about 1.1 to 1 against it — the car appeared to float on bare
    /// rims with no tyres at all. Lightening the tyre is not the fix: every
    /// tone light enough to separate from the panel is one the bodywork
    /// already occupies, so the wheels would vanish into the car instead of
    /// into the background. The outline separates them while the tyre itself
    /// stays the darkest thing in the drawing, as it is in life.
    ///
    /// In light mode it is the tyre's own colour, so it draws nothing.
    static let tyreEdge = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(hex: 0x747F84)
            : UIColor(hex: 0x24292B)
    })
}

/// The tones one paint colour is drawn in.
///
/// Four values rather than one, so the illustration has a body, a shaded lower
/// section, a glass tone that suits the paint and a trim tone — which is what
/// stops it looking like a flat sticker.
struct VehiclePaintTones {
    var body: Color
    var shade: Color
    var glass: Color
    var trim: Color

    /// Tones are fixed rather than semantic: a red car is red in both
    /// appearances. What changes with appearance is the ground it sits on and
    /// the label beside it, which are tokens.
    static func tones(for paint: VehiclePaintColor) -> VehiclePaintTones {
        func rgb(_ hex: UInt32) -> Color { Color(uiColor: UIColor(hex: hex)) }
        switch paint {
        case .slate:
            return VehiclePaintTones(body: rgb(0x4A5A60), shade: rgb(0x36454A), glass: rgb(0x9FB4BA), trim: rgb(0x263034))
        case .black:
            return VehiclePaintTones(body: rgb(0x2B3033), shade: rgb(0x1C2022), glass: rgb(0x8A9BA1), trim: rgb(0x121517))
        case .white:
            return VehiclePaintTones(body: rgb(0xF0F2F2), shade: rgb(0xD2D8D9), glass: rgb(0x9EB0B6), trim: rgb(0x8C9699))
        case .silver:
            return VehiclePaintTones(body: rgb(0xBFC7C9), shade: rgb(0x9BA5A8), glass: rgb(0x8FA3A9), trim: rgb(0x6E787B))
        case .red:
            return VehiclePaintTones(body: rgb(0xA8322B), shade: rgb(0x81231E), glass: rgb(0xA8BCC1), trim: rgb(0x5C1815))
        case .blue:
            return VehiclePaintTones(body: rgb(0x2E5C7A), shade: rgb(0x21455C), glass: rgb(0xA3BAC4), trim: rgb(0x16303F))
        case .green:
            return VehiclePaintTones(body: rgb(0x38614B), shade: rgb(0x284838), glass: rgb(0xA2BAAF), trim: rgb(0x1A3024))
        case .orange:
            return VehiclePaintTones(body: rgb(0xC26126), shade: rgb(0x99491A), glass: rgb(0xB0BFC2), trim: rgb(0x6B3212))
        case .sand:
            return VehiclePaintTones(body: rgb(0xC3B08A), shade: rgb(0xA08E6E), glass: rgb(0xA8B7B8), trim: rgb(0x6F6248))
        }
    }
}

/// One vehicle, drawn.
///
/// Draws the owner's photo, an exact illustration or a body-style silhouette,
/// in that order — the caller supplies the resolution so the decision is made
/// once, in `VehicleArtworkResolver`, not per view.
struct VehicleArtworkView: View {
    let resolution: VehicleArtworkResolution
    var paint: VehiclePaintColor = .default
    var photo: UIImage?
    /// The label a screen reader hears. The picture itself is decoration; this
    /// says what it is a picture of.
    var accessibilityText: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    var body: some View {
        content
            .scaleEffect(hasAppeared || reduceMotion ? 1 : 0.96)
            .opacity(hasAppeared || reduceMotion ? 1 : 0)
            .animation(.smooth(duration: 0.35), value: hasAppeared)
            .onAppear { hasAppeared = true }
            .accessibilityElement()
            .accessibilityLabel(Text(accessibilityText))
    }

    @ViewBuilder
    private var content: some View {
        switch resolution {
        case .photo(let id):
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .clipped()
                    .accessibilityIdentifier("artwork.photo.\(id.uuidString)")
            } else {
                // Photo mode with nothing loaded yet: the ground, not a gap,
                // so the card does not jump when the image arrives.
                Theme.Palette.artworkGround
            }
        case .matchedIllustration(let illustration):
            VehicleSilhouetteView(shape: .illustration(illustration), paint: paint)
        case .bodyStyleIllustration(let style):
            VehicleSilhouetteView(shape: .bodyStyle(style), paint: paint)
        case .unknownShape:
            Image(systemName: "car.side")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(Theme.Palette.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Which drawing to use, so the silhouette view takes one value rather than
/// two optionals.
enum VehicleShape: Hashable {
    case illustration(VehicleIllustration)
    case bodyStyle(VehicleBodyStyle)
}

/// The drawing itself.
struct VehicleSilhouetteView: View {
    let shape: VehicleShape
    var paint: VehiclePaintColor = .default

    var body: some View {
        let tones = VehiclePaintTones.tones(for: paint)
        GeometryReader { proxy in
            let scale = min(
                proxy.size.width / VehicleArt.boxSize.width,
                proxy.size.height / VehicleArt.boxSize.height
            )
            let drawn = CGSize(
                width: VehicleArt.boxSize.width * scale,
                height: VehicleArt.boxSize.height * scale
            )
            let origin = CGPoint(
                x: (proxy.size.width - drawn.width) / 2,
                y: (proxy.size.height - drawn.height) / 2
            )

            Canvas { context, _ in
                context.translateBy(x: origin.x, y: origin.y)
                context.scaleBy(x: scale, y: scale)
                VehicleDrawing.draw(shape, tones: tones, in: &context)
            }
        }
        .aspectRatio(VehicleArt.aspectRatio, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
