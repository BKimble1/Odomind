import SwiftUI
import OdomindCore

/// A compact status chip. Small on purpose: the list is the content, not the
/// badges.
struct DueBadge: View {
    let state: DueState
    var compact: Bool = false

    var body: some View {
        Group {
            if compact {
                Image(systemName: state.symbolName)
            } else {
                Label(state.displayName, systemImage: state.symbolName)
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(state.tint)
        .accessibilityLabel(Text(state.displayName))
    }
}

/// Where a value came from, and whether anyone checked it.
///
/// Shown under every schedule and every specification. The word "Verified"
/// appears only when a person checked the value against a citable manufacturer
/// source and recorded the date.
struct ProvenanceLabel: View {
    let provenance: Provenance
    var sourceName: String?

    var body: some View {
        HStack(spacing: Theme.Spacing.tight) {
            Image(systemName: provenance.origin.symbolName)
                .imageScale(.small)
            Text(text)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Source: \(text)"))
    }

    private var text: String {
        var parts: [String] = [provenance.origin.shortLabel]

        if let name = sourceName ?? provenance.attribution?.sourceName, !name.isEmpty {
            parts.append(name)
        }

        if provenance.isVerified, let reviewed = provenance.attribution?.reviewedOn {
            parts.append("verified \(Format.date(reviewed))")
        }
        return parts.joined(separator: " · ")
    }
}

/// An explanatory note inside a list. Used for the things Odomind will not
/// claim, which is often the most useful thing on the screen.
struct InlineNotice: View {
    enum Kind {
        case information
        case caution
        case safety

        var symbolName: String {
            switch self {
            case .information: return "info.circle"
            case .caution: return "exclamationmark.triangle"
            case .safety: return "shield.lefthalf.filled"
            }
        }

        var tint: Color {
            switch self {
            case .information: return .secondary
            case .caution: return Theme.Colors.caution
            case .safety: return Theme.Colors.informative
            }
        }
    }

    var kind: Kind = .information
    let message: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.small) {
            Image(systemName: kind.symbolName)
                .foregroundStyle(kind.tint)
                .imageScale(.small)
                .accessibilityHidden(true)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Marks content that came from the built-in sample vehicle.
///
/// One component rather than three near-identical inline copies, so the mark
/// cannot end up saying "SAMPLE" on one screen and "SAMPLE DATA" on another,
/// and so its contrast is fixed in one place.
struct SampleBadge: View {
    var body: some View {
        Text("SAMPLE")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: Theme.Radius.badge))
            .foregroundStyle(Theme.Colors.caution)
            .accessibilityLabel(Text("Sample data"))
    }
}

/// A label and value on one line, wrapping gracefully at large text sizes.
struct ValueRow: View {
    let label: String
    let value: String
    var secondary: String?
    var symbolName: String?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                content
            }
            .accessibilityElement(children: .combine)
        } else {
            HStack(alignment: .firstTextBaseline) {
                content
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var content: some View {
        HStack(spacing: Theme.Spacing.small) {
            if let symbolName {
                Image(systemName: symbolName)
                    .foregroundStyle(.secondary)
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
            Text(label)
        }
        if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: Theme.Spacing.small) }
        VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 0) {
            Text(value)
                .foregroundStyle(.primary)
            if let secondary {
                Text(secondary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The "we do not have this" row.
///
/// Odomind shows this instead of a plausible-looking number whenever it does
/// not have a value it can stand behind, with a way to supply the real one.
struct UnavailableValueRow: View {
    let label: String
    var explanation: String = "Add it from your owner's manual or the door placard."
    var action: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if let action {
            // The whole row is the control. A caption-sized "Add this value"
            // link under it read as a second thing to aim at, and was too
            // small to hit reliably.
            Button(action: action) { content }
                .foregroundStyle(.primary)
                .accessibilityHint(Text("Record the \(label) for this vehicle"))
        } else {
            content
        }
    }

    private var content: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.small) {
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                // Side by side, a long name and "Not available" squeeze each
                // other until one of them clips. Stacked once the text is
                // large, neither has to give way.
                if dynamicTypeSize.isAccessibilitySize {
                    Text(label)
                    Text("Not available")
                        .foregroundStyle(.secondary)
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        Text(label)
                        Spacer(minLength: Theme.Spacing.small)
                        Text("Not available")
                            .foregroundStyle(.secondary)
                    }
                }
                Text(explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if action != nil {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Build 2 surfaces

/// A raised card on the page.
///
/// One component so corner radius, padding and surface colour cannot drift,
/// and so the "giant card holding one sentence" the brief called out has a
/// single place to be fixed if it reappears.
struct Card<Content: View>: View {
    var padding: CGFloat = Theme.Spacing.large
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(Theme.Palette.raised, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }
}

/// A section heading on a scrolling page, with an optional trailing action.
struct SectionHeading<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.Palette.primaryText)
            Spacer(minLength: Theme.Spacing.small)
            trailing
        }
        .accessibilityAddTraits(.isHeader)
    }
}

extension SectionHeading where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title: title) { EmptyView() }
    }
}

/// The filled primary action.
///
/// Height comes from padding rather than `controlSize(.large)`, which pins the
/// button's own font and shows up in the accessibility audit as partially
/// unsupported Dynamic Type. The label grows rather than truncating, because
/// dropping the control size once fixed the pinned font and left the label
/// clipping instead.
struct PrimaryActionButton: View {
    let title: String
    var isProminent: Bool = true
    var symbolName: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.small) {
                if let symbolName {
                    Image(systemName: symbolName)
                        .imageScale(.small)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.body.weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .foregroundStyle(isProminent ? Theme.Palette.onAccent : Theme.Palette.accent)
        .background(
            isProminent ? AnyShapeStyle(Theme.Palette.accent) : AnyShapeStyle(Theme.Palette.recessed),
            in: RoundedRectangle(cornerRadius: Theme.Radius.tile)
        )
        // A control this size is comfortably over the 44pt minimum at default
        // text sizes; the floor keeps it there when the label is one short word.
        .frame(minHeight: Theme.minimumTapTarget)
    }
}

/// A small pill used for a filter, a segment or a tag.
struct Chip: View {
    let title: String
    var symbolName: String?
    var isSelected: Bool = false
    var tint: Color = Theme.Palette.accent

    var body: some View {
        HStack(spacing: Theme.Spacing.tight) {
            if let symbolName {
                Image(systemName: symbolName)
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
            Text(title)
        }
        .font(.subheadline.weight(isSelected ? .semibold : .regular))
        .foregroundStyle(isSelected ? Theme.Palette.onAccent : Theme.Palette.primaryText)
        .padding(.horizontal, Theme.Spacing.medium)
        .padding(.vertical, Theme.Spacing.small)
        .background(
            isSelected ? AnyShapeStyle(tint) : AnyShapeStyle(Theme.Palette.recessed),
            in: Capsule()
        )
    }
}

/// The one-line explanation Odomind puts under something it cannot promise.
///
/// Small, quiet, and one sentence. The brief's complaint about Build 1 was
/// three cards saying the same uncertainty; this exists so there is one place
/// that says it.
struct QuietNote: View {
    let text: String
    var symbolName: String = "info.circle"

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.small) {
            Image(systemName: symbolName)
                .imageScale(.small)
                .foregroundStyle(Theme.Palette.secondaryText)
                .accessibilityHidden(true)
            Text(text)
                .font(.footnote)
                .foregroundStyle(Theme.Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
