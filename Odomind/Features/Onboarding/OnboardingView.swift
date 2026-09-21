import SwiftUI
import OdomindCore

/// The first screen. Short, honest, and skippable.
///
/// No account, no permissions, no questions about what kind of driver you are.
/// One decision: add your vehicle, or look around with a sample first.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var showingAddVehicle = false

    /// A fixed point size does not grow with the owner's text setting, which
    /// XCTest's accessibility audit reports as partially unsupported Dynamic
    /// Type. Scaled against a text style, the symbol grows with everything
    /// else on the screen.
    @ScaledMetric(relativeTo: .largeTitle) private var heroSymbolSize: CGFloat = 52

    var body: some View {
        // Scrollable, because this screen has no way to shed content. As a
        // plain VStack it clipped its own text — the audit found five clipped
        // elements here, including the tagline and every promise row. The
        // GeometryReader keeps the old centred look when everything fits and
        // lets it scroll when it does not.
        GeometryReader { proxy in
            ScrollView {
                content
                    .padding(Theme.Spacing.section)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $showingAddVehicle) {
            AddVehicleFlow()
        }
    }

    private var content: some View {
        VStack(spacing: Theme.Spacing.section) {
            Spacer(minLength: 0)

            VStack(spacing: Theme.Spacing.medium) {
                Image(systemName: "car.side")
                    .font(.system(size: heroSymbolSize, weight: .light))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)

                Text("Odomind")
                    .font(.largeTitle.weight(.semibold))
                Text("Know your car. Know what's next.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.large) {
                PromiseRow(
                    symbolName: "gauge.with.dots.needle.33percent",
                    title: "You tell it your mileage",
                    detail: "Odomind cannot read your car. One number, whenever you think of it, is enough."
                )
                PromiseRow(
                    symbolName: "checkmark.seal",
                    title: "It says what it knows",
                    detail: "Where Odomind does not have a value, it says so instead of showing a plausible guess."
                )
                PromiseRow(
                    symbolName: "iphone",
                    title: "It stays on your phone",
                    detail: "No account, no sign-in, nothing uploaded. It works offline."
                )
            }
            .padding(.horizontal, Theme.Spacing.small)

            Spacer(minLength: 0)

            VStack(spacing: Theme.Spacing.medium) {
                Button {
                    showingAddVehicle = true
                } label: {
                    Text("Add my vehicle")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("onboarding.addVehicle")

                // A plain text button here was about twenty points tall,
                // well under the forty-four a finger needs. Bordered gives it
                // a real target and keeps the two choices clearly ranked.
                Button {
                    model.addDemoContent()
                } label: {
                    Text("Try a sample vehicle")
                        .font(.body)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier("onboarding.addSample")
            }
        }
    }
}

private struct PromiseRow: View {
    let symbolName: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.medium) {
            Image(systemName: symbolName)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(detail)
                    // Footnote rather than caption: secondary text this small
                    // sits right on the contrast threshold, and this is the
                    // first thing anyone reads about what the app will do.
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
