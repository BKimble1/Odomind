import SwiftUI
import UserNotifications
import OdomindCore

@main
struct OdomindApp: App {
    @State private var launch: LaunchState = .loading
    @State private var router = NavigationRouter()

    var body: some Scene {
        WindowGroup {
            Group {
                switch launch {
                case .loading:
                    LaunchProgressView()
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
            .preferredColorScheme(Self.forcedColorScheme)
        }
    }

    /// Honours `-odomind-appearance dark` (or `light`) under UI testing.
    ///
    /// The screenshot pass needs to capture both appearances, and setting
    /// `XCUIDevice.shared.appearance` before launch did not take: the run that
    /// was meant to be dark came back byte-for-byte identical to the light
    /// one, which is a quiet way to ship an unverified dark mode. Asking the
    /// app directly cannot silently do nothing.
    ///
    /// `nil` everywhere else, so the app follows the system as it should.
    private static var forcedColorScheme: ColorScheme? {
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

private struct LaunchProgressView: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.large) {
            ProgressView()
            Text("Opening your garage…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
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
