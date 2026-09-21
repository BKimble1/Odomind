import SwiftUI
import UserNotifications
import OdomindCore

@main
struct OdomindApp: App {
    @State private var launch: LaunchState = .loading
    @State private var router = NavigationRouter()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                switch launch {
                case .loading:
                    LaunchBrandingView()
                case .ready(let model):
                    RootView()
                        .environment(model)
                        .environment(router)
                case .failed(let message):
                    LaunchFailureView(message: message) {
                        launch = .loading
                        Task { await start() }
                    }
                }
            }
            .task {
                guard case .loading = launch else { return }
                await start()
            }
            .onOpenURL { url in
                if let link = DeepLink(urlString: url.absoluteString) {
                    router.follow(link)
                }
            }
            .odomindAppearance(appearance)
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, case .ready(let model) = launch else { return }
                Task {
                    // Re-reading StoreKit on return catches a renewal, a
                    // refund or a cancellation made in the App Store while
                    // Odomind was in the background.
                    await model.entitlements.refreshEntitlement()
                    // Never at launch, at most once a day, and only if the
                    // owner turned it on. A catalog check has no business on
                    // the path to the first screen.
                    if model.isAutomaticCatalogCheckDue {
                        _ = await model.checkForCatalogUpdate()
                    }
                }
            }
        }
    }

    /// The appearance actually in force.
    ///
    /// The owner's stored choice once there is a model to read it from, the
    /// system default before that, and the UI-testing override above
    /// everything so the screenshot pass can capture both appearances.
    private var appearance: AppearancePreference {
        if let forced = Self.forcedAppearance { return forced }
        guard case .ready(let model) = launch else { return .system }
        return model.snapshot.settings.preferences.appearance
    }

    /// Honours `-odomind-appearance dark` (or `light`) under UI testing.
    ///
    /// The screenshot pass needs to capture both appearances, and setting
    /// `XCUIDevice.shared.appearance` before launch did not take: the run that
    /// was meant to be dark came back byte-for-byte identical to the light
    /// one, which is a quiet way to ship an unverified dark mode. Asking the
    /// app directly cannot silently do nothing.
    ///
    /// `nil` everywhere else, so the app follows the owner's own choice.
    private static var forcedAppearance: AppearancePreference? {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains(AppModel.uiTestingArgument),
              let index = arguments.firstIndex(of: "-odomind-appearance"),
              arguments.indices.contains(index + 1)
        else { return nil }

        switch arguments[index + 1].lowercased() {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }

    @MainActor
    private func start() async {
        do {
            let model = try AppModel.live()
            await model.load()
            _ = model.applyCatalogUpdateIfNeeded()

            NotificationDelegate.shared.onDeepLink = { link in
                router.follow(link)
            }
            UNUserNotificationCenter.current().delegate = NotificationDelegate.shared

            launch = .ready(model)
        } catch {
            launch = .failed((error as? LocalizedError)?.errorDescription ?? String(describing: error))
        }
    }
}

enum LaunchState {
    case loading
    case ready(AppModel)
    case failed(String)
}

/// The app's own copy of the launch screen.
///
/// Deliberately identical to the static one in `Info.plist` — same emblem,
/// same white, same position — so the handover is invisible. It adds the one
/// thing a `UILaunchScreen` cannot draw: the line of text at the bottom.
///
/// There is no progress indicator, no percentage and no timer. This is on
/// screen for exactly as long as opening the local store takes, and the app
/// enters the moment that finishes. A branded screen that outstays the work it
/// is covering is an advertisement, not a launch.
private struct LaunchBrandingView: View {
    var body: some View {
        ZStack {
            // Named rather than the generated asset symbol: this project's
            // build settings do not turn on Swift asset symbol generation, and
            // a missing symbol is a build break rather than a missing image.
            Color("LaunchBackground")
                .ignoresSafeArea()

            Image("LaunchEmblem")
                .resizable()
                .scaledToFit()
                .frame(width: 168)
                .accessibilityHidden(true)

            VStack {
                Spacer()
                Text("Powered by Idlery")
                    .font(.footnote)
                    // Fixed against the white launch background rather than
                    // semantic, because this screen is white in both
                    // appearances and `.secondary` would invert with the
                    // system setting and vanish.
                    .foregroundStyle(Color(uiColor: UIColor(hex: 0x536166)))
                    .padding(.bottom, Theme.Spacing.section)
            }
        }
        // One element, read once. The emblem is decoration and the sentence is
        // the content.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Odomind. Powered by Idlery."))
    }
}

/// Shown when the store itself could not be opened.
///
/// A real failure gets a real screen: what happened, and what the owner can do,
/// rather than a blank page or a crash.
private struct LaunchFailureView: View {
    let message: String
    let retry: () -> Void

    /// Scaled rather than fixed, so the symbol grows with the text beneath it.
    @ScaledMetric(relativeTo: .largeTitle) private var symbolSize: CGFloat = 44

    var body: some View {
        VStack(spacing: Theme.Spacing.large) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: symbolSize))
                .foregroundStyle(.secondary)
            Text("Odomind could not open your data")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("Your records have not been changed. Try again, and if this keeps happening you can restore from a backup after reinstalling.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try again", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .padding(Theme.Spacing.section)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

/// Handles notification taps and foreground delivery.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    var onDeepLink: ((DeepLink) -> Void)?

    /// Reminders still show while the app is open. A deadline the owner is
    /// looking at should not be silently swallowed because they happened to
    /// have Odomind on screen.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let raw = response.notification.request.content.userInfo["deepLink"] as? String,
              let link = DeepLink(urlString: raw) else { return }
        await MainActor.run {
            self.onDeepLink?(link)
        }
    }
}
