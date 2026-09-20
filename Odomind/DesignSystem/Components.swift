import SwiftUI
import OdomindCore

/// A compact status chip. Small on purpose: the list is the content, not the
/// badges.
struct DueBadge: View {
    let state: DueState
    var compact: Bool = false

    var body: some View {
        Label {
            Text(state.displayName)
        } icon: {
            Image(systemName: state.symbolName)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(state.tint)
        .labelStyle(compact ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))
        .accessibilityLabel(Text(state.displayName))
    }
}

/// Type-erased label style so a single view can switch between them.
struct AnyLabelStyle: LabelStyle {
    private let makeBodyClosure: (Configuration) -> AnyView

    init<S: LabelStyle>(_ style: S) {
        makeBodyClosure = { configuration in
            AnyView(style.makeBody(configuration: configuration))
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        makeBodyClosure(configuration)
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
            case .caution: return .orange
            case .safety: return .blue
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
    var explanation: String = "Not available. Add it from your owner's manual or door placard."
    var action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            HStack {
                Text(label)
                Spacer()
                Text("Not available")
                    .foregroundStyle(.secondary)
            }
            Text(explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let action {
                Button("Add this value", action: action)
                    .font(.caption.weight(.medium))
                    .buttonStyle(.borderless)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// A prominent action used sparingly: update mileage, log a service.
struct PrimaryActionButton: View {
    let title: String
    let symbolName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbolName)
                .font(.body.weight(.medium))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }
}
