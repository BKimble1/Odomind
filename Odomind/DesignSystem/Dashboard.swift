import SwiftUI
import OdomindCore

// The surface Build 4 is built on: a light page lit from one place, white
// cards floating on it, and colour carried by small chips rather than by the
// cards themselves.
//
// Everything here is shared. A screen that draws its own card, its own chip or
// its own pill is a screen that will drift, and the last release had five
// slightly different card treatments to prove it.

/// The page, lit from one place.
///
/// Two soft radials over the page colour. Both fade to the *same* colour at
/// zero opacity rather than to `.clear`: `.clear` is transparent black, so a
/// gradient running into it passes through grey and leaves the dirty edge that
/// makes a blend look cheap.
struct LuminousField: View {
    /// Dialled back on the screens that are mostly list, so the field reads as
    /// one light source across the app rather than a pattern on every page.
    var strength: Double = 1

    var body: some View {
        ZStack {
            Theme.Palette.page
            GeometryReader { geo in
                let d = max(geo.size.width, geo.size.height)
                RadialGradient(
                    colors: [
                        Theme.Palette.fieldPrimary.opacity(0.17 * strength),
                        Theme.Palette.fieldPrimary.opacity(0),
                    ],
                    center: UnitPoint(x: 0.5, y: 0.02),
                    startRadius: 0,
                    endRadius: d * 0.78
                )
                RadialGradient(
                    colors: [
                        Theme.Palette.fieldSecondary.opacity(0.13 * strength),
                        Theme.Palette.fieldSecondary.opacity(0),
                    ],
                    center: UnitPoint(x: 0.96, y: 0.68),
                    startRadius: 0,
                    endRadius: d * 0.55
                )
            }
        }
        .ignoresSafeArea()
    }
}

/// A white card on the field.
private struct CardSurface: ViewModifier {
    var radius: CGFloat
    var fill: Color

    func body(content: Content) -> some View {
        content
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.Palette.cardBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
    }
}

extension View {
    func cardSurface(
        radius: CGFloat = Theme.Radius.card,
        fill: Color = Theme.Palette.raised
    ) -> some View {
        modifier(CardSurface(radius: radius, fill: fill))
    }
}

/// A circular icon chip: a pastel ground with a glyph on it.
struct IconChip: View {
    let symbol: String
    var ground: Color = Theme.Palette.chipAccent
    var tint: Color = Theme.Palette.accent
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(ground, in: Circle())
            .accessibilityHidden(true)
    }
}

/// The one-word verdict under the vehicle's name.
///
/// A word and an icon, never colour alone: the same state has to survive a
/// greyscale screenshot and a colour-blind reader.
struct StatusPill: View {
    let text: String
    let symbol: String
    var ground: Color
    var tint: Color

    var body: some View {
        HStack(spacing: Theme.Spacing.tight + 2) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
            Text(text)
                .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(tint)
        .padding(.leading, 9)
        .padding(.trailing, 13)
        .padding(.vertical, 6)
        .background(ground, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// One of the three at-a-glance numbers.
struct StatTile: View {
    let symbol: String
    let ground: Color
    let tint: Color
    let label: String
    let value: String
    var unit: String?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: Theme.Spacing.small) {
            IconChip(symbol: symbol, ground: ground, tint: tint, size: 40)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.Palette.secondaryText)
                .multilineTextAlignment(.center)
            // Stacked at accessibility sizes: "Over" and "due" beside each
            // other in a third of the screen width hyphenates both.
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 0) { valueText; unitText }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 3) { valueText; unitText }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.large - 2)
        .padding(.horizontal, Theme.Spacing.small)
        .cardSurface(radius: Theme.Radius.tile)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(label): \(value) \(unit ?? "")"))
    }

    private var valueText: some View {
        Text(value)
            .font(.title3.weight(.bold))
            .foregroundStyle(Theme.Palette.primaryText)
    }

    @ViewBuilder
    private var unitText: some View {
        if let unit {
            Text(unit)
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.Palette.secondaryText)
        }
    }
}

/// The warm card for something that is about a date rather than a distance —
/// an inspection, a registration, anything the odometer cannot see coming.
struct AttentionCard: View {
    let symbol: String
    let title: String
    let detail: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.medium) {
                IconChip(
                    symbol: symbol,
                    ground: Theme.Palette.chipCaution,
                    tint: Theme.Colors.caution
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Theme.Palette.primaryText)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.secondaryText)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Theme.Spacing.small)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .accessibilityHidden(true)
            }
            .padding(Theme.Spacing.large - 1)
            .cardSurface(fill: Theme.Palette.cautionSurface)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// A section card: a title row with an optional chevron, then content.
struct PanelCard<Content: View>: View {
    let symbol: String
    let title: String
    var action: (() -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            content
        }
        .padding(Theme.Spacing.large - 1)
        .cardSurface()
    }

    @ViewBuilder
    private var header: some View {
        if let action {
            Button(action: action) {
                headerRow(showsChevron: true).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            headerRow(showsChevron: false)
        }
    }

    private func headerRow(showsChevron: Bool) -> some View {
        HStack(spacing: Theme.Spacing.small + 2) {
            Image(systemName: symbol)
                .font(.callout.weight(.semibold))
                .foregroundStyle(Theme.Palette.primaryText)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.Palette.primaryText)
            Spacer(minLength: Theme.Spacing.small)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// A date on a tinted ground, as it appears beside a job.
struct DateChip: View {
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "calendar")
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(Theme.Palette.accent)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Theme.Palette.chipAccent, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
