import Foundation
import OdomindCore
import UserNotifications

enum NotificationAuthorization: String, Sendable, Hashable {
    case notDetermined
    case denied
    case authorized
    case provisional

    var allowsScheduling: Bool { self == .authorized || self == .provisional }
}

/// The notification surface Odomind uses, behind a protocol.
///
/// `ReminderCoordinator` is the interesting part — dedupe, cancellation,
/// bounding — and it is tested against an in-memory implementation rather than
/// against the real notification centre, which cannot be exercised in a
/// simulator test run.
protocol NotificationScheduling: Sendable {
    func authorizationStatus() async -> NotificationAuthorization
    /// Asks the system for permission. Called when the owner turns a reminder
    /// on, never at launch.
    func requestAuthorization() async -> Bool
    func pending() async -> [PendingReminder]
    /// Returns identifiers that could not be scheduled, with the reason.
    func schedule(_ requests: [ReminderRequest]) async -> [String: String]
    func cancel(identifiers: [String]) async
    func cancelAll() async
}

/// The real implementation, backed by `UNUserNotificationCenter`.
struct SystemNotificationScheduler: NotificationScheduling {
    private var center: UNUserNotificationCenter { UNUserNotificationCenter.current() }

    func authorizationStatus() async -> NotificationAuthorization {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized: return .authorized
        case .provisional: return .provisional
        case .ephemeral: return .authorized
        @unknown default: return .notDetermined
        }
    }

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func pending() async -> [PendingReminder] {
        let requests = await center.pendingNotificationRequests()
        return requests.compactMap { request in
            guard let trigger = request.trigger as? UNCalendarNotificationTrigger,
                  let date = trigger.nextTriggerDate() else { return nil }
            return PendingReminder(id: request.identifier, fireDate: date)
        }
    }

    func schedule(_ requests: [ReminderRequest]) async -> [String: String] {
        var failures: [String: String] = [:]
        for request in requests {
            let content = UNMutableNotificationContent()
            content.title = request.title
            content.body = request.body
            content.sound = .default
            content.userInfo = ["deepLink": request.deepLink, "kind": request.kind.rawValue]
            content.threadIdentifier = request.vehicleID.uuidString

            // A calendar trigger built from local components rather than a time
            // interval, so the reminder lands at the owner's chosen local time
            // even across a daylight-saving change.
            var components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: request.fireDate
            )
            components.second = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

            let notification = UNNotificationRequest(
                identifier: request.id,
                content: content,
                trigger: trigger
            )
            do {
                try await center.add(notification)
            } catch {
                failures[request.id] = error.localizedDescription
            }
        }
        return failures
    }

    func cancel(identifiers: [String]) async {
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func cancelAll() async {
        center.removeAllPendingNotificationRequests()
    }
}

/// A test double that records what it was asked to do.
final class InMemoryNotificationScheduler: NotificationScheduling, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: PendingReminder] = [:]

    var authorization: NotificationAuthorization
    var grantsAuthorization: Bool
    private(set) var authorizationRequestCount = 0
    private(set) var scheduledCalls: [[String]] = []
    private(set) var cancelledIdentifiers: [String] = []

    init(authorization: NotificationAuthorization = .authorized, grantsAuthorization: Bool = true) {
        self.authorization = authorization
        self.grantsAuthorization = grantsAuthorization
    }

    func authorizationStatus() async -> NotificationAuthorization {
        lock.lock(); defer { lock.unlock() }
        return authorization
    }

    func requestAuthorization() async -> Bool {
        lock.lock()
        authorizationRequestCount += 1
        let granted = grantsAuthorization
        authorization = granted ? .authorized : .denied
        lock.unlock()
        return granted
    }

    func pending() async -> [PendingReminder] {
        lock.lock(); defer { lock.unlock() }
        return storage.values.sorted { $0.fireDate < $1.fireDate }
    }

    func schedule(_ requests: [ReminderRequest]) async -> [String: String] {
        lock.lock()
        scheduledCalls.append(requests.map(\.id))
        for request in requests {
            storage[request.id] = PendingReminder(id: request.id, fireDate: request.fireDate)
        }
        lock.unlock()
        return [:]
    }

    func cancel(identifiers: [String]) async {
        lock.lock()
        cancelledIdentifiers.append(contentsOf: identifiers)
        for identifier in identifiers { storage.removeValue(forKey: identifier) }
        lock.unlock()
    }

    func cancelAll() async {
        lock.lock()
        cancelledIdentifiers.append(contentsOf: storage.keys)
        storage.removeAll()
        lock.unlock()
    }
}
