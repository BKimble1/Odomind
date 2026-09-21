import CoreLocation
import SwiftUI

/// The two permissions Odomind asks for up front, and nothing else.
///
/// The brief puts these before the vehicle flow because both are about what
/// the app can do for the owner rather than about the car: reminders so it can
/// tell them something is due, location so Parts can find a shop without being
/// asked where they are every time.
///
/// Deliberately not here: calendar, camera and purchases. Each of those is
/// asked for at the moment it is needed — the calendar when something is
/// exported, the camera when a VIN is scanned — and stacking five system
/// dialogues into a welcome sequence is how people learn to refuse all of
/// them.
///
/// Every prompt follows a tap. Nothing is requested on appearance, and both
/// can be skipped without the app becoming less usable.
struct PermissionSetupView: View {
    @Environment(AppModel.self) private var model

    let onDone: () -> Void

    @State private var remindersAnswered = false
    @State private var locationAnswered = false
    @State private var isAsking = false

    private var remindersOn: Bool { model.snapshot.settings.reminders.remindersEnabled }
    private var locationStatus: CLAuthorizationStatus { model.shoppingLocation.authorizationStatus }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.section) {
            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                Text("Two quick things")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Theme.Palette.primaryText)
                Text("Both are optional, and Odomind works without either.")
                    .font(.body)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            permissionRow(
                symbol: "bell",
                title: "Maintenance reminders",
                detail: "Odomind tells you when something is coming up. It only asks iOS for permission if you say yes here.",
                settled: remindersOn || remindersAnswered,
                settledNote: remindersOn ? "Reminders are on." : "No reminders for now. You can turn them on in Settings.",
                actionTitle: "Turn on reminders",
                identifier: "permissions.reminders"
            ) {
                isAsking = true
                _ = await model.enableReminders()
                remindersAnswered = true
                isAsking = false
            } onSkip: {
                remindersAnswered = true
            }

            permissionRow(
                symbol: "location",
                title: "Parts shops near you",
                detail: "Used only to list shops in your area, and only when you ask. You can type a town or postal code instead.",
                settled: locationSettled,
                settledNote: locationSettledNote,
                actionTitle: "Use my location",
                identifier: "permissions.location"
            ) {
                isAsking = true
                _ = await model.shoppingLocation.requestPermission()
                locationAnswered = true
                isAsking = false
            } onSkip: {
                locationAnswered = true
            }

            Spacer(minLength: 0)

            PrimaryActionButton(title: "Continue") { onDone() }
                .accessibilityIdentifier("permissions.continue")

            Text("No account, and nothing about you is uploaded.")
                .font(.footnote)
                .foregroundStyle(Theme.Palette.secondaryText)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(Theme.Spacing.large)
    }

    private var locationSettled: Bool {
        locationAnswered || locationStatus != .notDetermined
    }

    private var locationSettledNote: String {
        switch locationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return "Odomind can find shops near you."
        case .denied, .restricted:
            return "No location. Type a town or postal code in Parts instead."
        default:
            return "No location for now. You can turn it on in Settings."
        }
    }

    @ViewBuilder
    private func permissionRow(
        symbol: String,
        title: String,
        detail: String,
        settled: Bool,
        settledNote: String,
        actionTitle: String,
        identifier: String,
        onAsk: @escaping () async -> Void,
        onSkip: @escaping () -> Void
    ) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                Label(title, systemImage: symbol)
                    .font(.headline)
                    .foregroundStyle(Theme.Palette.primaryText)

                if settled {
                    Text(settledNote)
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: Theme.Spacing.medium) {
                        Button(actionTitle) {
                            Task { await onAsk() }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Palette.accent)
                        .buttonStyle(.tappableText)
                        .disabled(isAsking)
                        .accessibilityIdentifier(identifier)

                        Button("Not now", action: onSkip)
                            .font(.subheadline)
                            .foregroundStyle(Theme.Palette.secondaryText)
                            .buttonStyle(.tappableText)
                            .accessibilityIdentifier("\(identifier).skip")
                    }
                }
            }
        }
    }
}
