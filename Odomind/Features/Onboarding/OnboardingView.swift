import SwiftUI
import OdomindCore

/// The first screen. One sentence, one decision, and an early yes-or-no on
/// reminders.
///
/// Apple's notification dialog appears only if the owner taps "Enable
/// reminders" — never on its own, and never stacked with location, calendar or
/// a purchase prompt. There is no paywall anywhere in setup.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model

    @State private var showingAddVehicle = false
    @State private var remindersDecided = false
    @State private var isRequestingReminders = false
    /// The permission questions come before the vehicle flow, which is the
    /// owner's stated preference and also the better order: both are about
    /// what the app may do, and neither depends on knowing the car.
    @State private var showingPermissions = false
    /// Asked before anything else, and only once.
    @State private var showingInterests = false

    /// A fixed point size does not grow with the owner's text setting, which
    /// XCTest's accessibility audit reports as partially unsupported Dynamic
    /// Type. Scaled against a text style, the symbol grows with everything
    /// else on the screen.
    @ScaledMetric(relativeTo: .largeTitle) private var heroSymbolSize: CGFloat = 52

    var body: some View {
        // Scrollable, because this screen has no way to shed content. As a
        // plain VStack it clipped its own text — the audit found five clipped
        // elements here, including the tagline and every promise row.
        GeometryReader { proxy in
            ScrollView {
                content
                    .padding(Theme.Spacing.section)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(LuminousField())
        .sheet(isPresented: $showingAddVehicle) {
            AddVehicleFlow()
        }
        .sheet(isPresented: $showingPermissions) {
            PermissionSetupView {
                model.markPermissionSetupSeen()
                showingPermissions = false
                showingAddVehicle = true
            }
            .interactiveDismissDisabled(false)
        }
        .sheet(isPresented: $showingInterests) {
            TrackingInterestsView {
                showingInterests = false
                if shouldOfferPermissions {
                    showingPermissions = true
                } else {
                    showingAddVehicle = true
                }
            }
        }
    }

    /// Whether to put the permission questions before the vehicle flow.
    ///
    /// Only once. Somebody who said no is not asked again on the next launch —
    /// a refusal is an answer, and re-asking is how an app becomes something
    /// people dismiss reflexively.
    private var shouldOfferPermissions: Bool {
        AppModel.shouldOfferPermissionStep && !model.preferences.hasSeenPermissionSetup
    }

    private var content: some View {
        VStack(spacing: Theme.Spacing.section) {
            Spacer(minLength: 0)

            VStack(spacing: Theme.Spacing.medium) {
                Image(systemName: "car.side")
                    .font(.system(size: heroSymbolSize, weight: .light))
                    .foregroundStyle(Theme.Palette.accent)
                    .accessibilityHidden(true)

                Text("Odomind")
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(Theme.Palette.primaryText)
                Text("Know what your car needs, before it needs it.")
                    .font(.title3)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            remindersCard

            VStack(spacing: Theme.Spacing.medium) {
                PrimaryActionButton(title: "Add my vehicle") {
                    // What you care about, then what the app may do, then the
                    // car. The first two are about the owner and take seconds;
                    // asking them after the vehicle flow means asking somebody
                    // who has just finished and wants to be done.
                    if !model.preferences.hasAnsweredTrackingQuestion {
                        showingInterests = true
                    } else if shouldOfferPermissions {
                        showingPermissions = true
                    } else {
                        showingAddVehicle = true
                    }
                }
                .accessibilityIdentifier("onboarding.addVehicle")

                Button("Look around with a sample first") {
                    model.addDemoContent()
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.Palette.accent)
                // A plain Button is about 20 points tall, which the audit
                // flagged as an unreachable target. The style gives the
                // button itself a 44pt body; a frame around it does not.
                .buttonStyle(.tappableText)
                .accessibilityIdentifier("onboarding.sample")
            }

            Text("No account. Your records stay on this device.")
                .font(.footnote)
                .foregroundStyle(Theme.Palette.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    /// The one permission question, asked once, with a real "not now".
    @ViewBuilder
    private var remindersCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                Label("Reminders", systemImage: "bell")
                    .font(.headline)
                    .foregroundStyle(Theme.Palette.primaryText)

                if model.snapshot.settings.reminders.remindersEnabled {
                    Text("Reminders are on. You can change the timing in Settings whenever you like.")
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                } else if remindersDecided {
                    Text("No reminders for now. You can turn them on any time in Settings.")
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Odomind can tell you when something is coming up. It only asks iOS for permission if you say yes here.")
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: Theme.Spacing.medium) {
                        Button("Enable reminders") {
                            Task {
                                isRequestingReminders = true
                                _ = await model.enableReminders()
                                isRequestingReminders = false
                                remindersDecided = true
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Palette.accent)
                        .buttonStyle(.tappableText)
                        .disabled(isRequestingReminders)
                        .accessibilityIdentifier("onboarding.enableReminders")

                        Button("Not now") { remindersDecided = true }
                            .font(.subheadline)
                            .foregroundStyle(Theme.Palette.secondaryText)
                            .buttonStyle(.tappableText)
                            .accessibilityIdentifier("onboarding.notNow")
                    }
                }
            }
        }
    }
}
