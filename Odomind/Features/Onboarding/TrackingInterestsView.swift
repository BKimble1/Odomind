import SwiftUI
import OdomindCore

/// The first thing Odomind asks, before it knows anything about the car:
/// what do you actually want to keep an eye on?
///
/// The answer narrows the starter plan. Build 3 handed every new owner
/// eighteen jobs and a screen of "Needs setup", which is a backlog rather than
/// a plan. Somebody who says "oil and filters" and nothing else gets four jobs
/// and can add the rest whenever they like.
///
/// Skippable, and skipping is a real answer: it means "give me the usual",
/// not "ask me again later".
struct TrackingInterestsView: View {
    @Environment(AppModel.self) private var model
    @State private var chosen: Set<TrackingInterest> = []
    var done: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                    header
                    options
                }
                .padding(Theme.Spacing.section)
            }
            footer
        }
        .background(LuminousField())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            Text("What do you want to keep an eye on?")
                .font(.title.weight(.bold))
                .foregroundStyle(Theme.Palette.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text("Pick any. You can change this later.")
                .font(.callout)
                .foregroundStyle(Theme.Palette.secondaryText)
        }
    }

    private var options: some View {
        VStack(spacing: Theme.Spacing.small + 2) {
            ForEach(TrackingInterest.allCases) { interest in
                InterestRow(interest: interest, isOn: chosen.contains(interest)) {
                    if chosen.contains(interest) {
                        chosen.remove(interest)
                    } else {
                        chosen.insert(interest)
                    }
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: Theme.Spacing.small) {
            Button {
                model.setTrackingInterests(chosen)
                done()
            } label: {
                Text(chosen.isEmpty ? "Show me the usual" : "Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Theme.Palette.accent)
            .accessibilityIdentifier("interests.continue")
        }
        .padding(Theme.Spacing.section)
    }
}

private struct InterestRow: View {
    let interest: TrackingInterest
    let isOn: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: Theme.Spacing.medium) {
                IconChip(
                    symbol: interest.symbol,
                    ground: isOn ? Theme.Palette.chipAccent : Theme.Palette.recessed,
                    tint: isOn ? Theme.Palette.accent : Theme.Palette.secondaryText
                )
                Text(interest.title)
                    .font(.headline)
                    .foregroundStyle(Theme.Palette.primaryText)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: Theme.Spacing.small)
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? Theme.Palette.accent : Theme.Palette.separator)
                    .accessibilityHidden(true)
            }
            .padding(Theme.Spacing.large - 2)
            .cardSurface()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("interest.\(interest.rawValue)")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}
