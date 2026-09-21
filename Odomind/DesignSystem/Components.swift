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

/// One of the two actions Today keeps within reach.
///
/// Text only. At two-up widths a symbol crowds the label into wrapping, and
/// neither "Update mileage" nor "Log service" needs a picture to be read.
/// Only one of the pair is prominent, so the screen has a primary action
/// rather than two competing blocks of colour.
struct PrimaryActionButton: View {
    let title: String
    var isProminent: Bool = true
    let action: () -> Void

    var body: some View {
        // Height comes from padding rather than `controlSize(.large)`. A large
        // control size pins the button's own font, which the accessibility
        // audit reports as partially unsupported Dynamic Type, and a fixed
        // height is what clipped the longer label on this pair.
        let label = Text(title)
            .font(.body.weight(.medium))
            .multilineTextAlignment(.center)
            // Grow rather than truncate. Dropping `controlSize(.large)` fixed
            // the pinned font but left the label clipping instead, which the
            // audit caught on the next run.
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

        Group {
            if isProminent {
                Button(action: action) { label }
                    .buttonStyle(.borderedProminent)
            } else {
                Button(action: action) { label }
                    .buttonStyle(.bordered)
            }
        }
    }
}
