import Foundation

public enum ReminderKind: String, Codable, Sendable, CaseIterable, Hashable {
    /// A deadline Odomind is confident about, from a calendar rule.
    case calendarDeadline
    /// A projection from recorded readings. Always labelled as an estimate.
    case estimatedMileage
    /// A nudge to update the odometer.
    case mileageUpdate

    public var isEstimate: Bool { self == .estimatedMileage }
}

/// A local notification Odomind wants scheduled.
///
/// `id` is stable across recomputation: it identifies the task and the kind but
/// not the date, so re-scheduling replaces the pending request instead of
/// stacking a second copy on top of it.
public struct ReminderRequest: Hashable, Sendable, Identifiable {
    public var id: String
    public var vehicleID: UUID
    public var planItemID: UUID?
    public var kind: ReminderKind
    public var fireDate: Date
    public var title: String
    public var body: String
    /// Deep link opened when the notification is tapped.
    public var deepLink: String

    public init(
        id: String,
        vehicleID: UUID,
        planItemID: UUID?,
        kind: ReminderKind,
        fireDate: Date,
        title: String,
        body: String,
        deepLink: String
    ) {
        self.id = id
        self.vehicleID = vehicleID
        self.planItemID = planItemID
        self.kind = kind
        self.fireDate = fireDate
        self.title = title
        self.body = body
        self.deepLink = deepLink
    }

    public static func identifier(planItemID: UUID, kind: ReminderKind) -> String {
        "task.\(planItemID.uuidString).\(kind.rawValue)"
    }

    public static func mileageIdentifier(vehicleID: UUID) -> String {
        "mileage.\(vehicleID.uuidString)"
    }
}

/// A request already registered with the system.
public struct PendingReminder: Hashable, Sendable {
    public var id: String
    public var fireDate: Date

    public init(id: String, fireDate: Date) {
        self.id = id
        self.fireDate = fireDate
    }
}

/// What to add and what to remove to bring the system in line with the plan.
public struct ReminderReconciliation: Hashable, Sendable {
    public var toSchedule: [ReminderRequest]
    public var toCancel: [String]
    public var unchanged: [String]

    public init(toSchedule: [ReminderRequest], toCancel: [String], unchanged: [String]) {
        self.toSchedule = toSchedule
        self.toCancel = toCancel
        self.unchanged = unchanged
    }

    public var isEmpty: Bool { toSchedule.isEmpty && toCancel.isEmpty }
}

public struct ReminderSettings: Codable, Hashable, Sendable {
    public var remindersEnabled: Bool
    public var mileageUpdateRemindersEnabled: Bool
    public var mileageUpdateIntervalDays: Int
    public var preferredHour: Int
    public var preferredMinute: Int
    public var includeEstimatedMileageReminders: Bool

    public init(
        remindersEnabled: Bool = false,
        mileageUpdateRemindersEnabled: Bool = false,
        mileageUpdateIntervalDays: Int = 30,
        preferredHour: Int = 9,
        preferredMinute: Int = 0,
        includeEstimatedMileageReminders: Bool = true
    ) {
        self.remindersEnabled = remindersEnabled
        self.mileageUpdateRemindersEnabled = mileageUpdateRemindersEnabled
        self.mileageUpdateIntervalDays = max(1, mileageUpdateIntervalDays)
        self.preferredHour = min(max(preferredHour, 0), 23)
        self.preferredMinute = min(max(preferredMinute, 0), 59)
        self.includeEstimatedMileageReminders = includeEstimatedMileageReminders
    }

    public static let `default` = ReminderSettings()
}

/// Turns schedule evaluations into a bounded, de-duplicated set of local
/// notification requests.
///
/// Pure and clock-injected, so the reconciliation logic can be tested without
/// touching `UNUserNotificationCenter`.
public enum ReminderPlanner {
    /// iOS keeps a limited number of pending local notifications per app and
    /// silently drops the rest. Odomind schedules comfortably under that limit
    /// and always keeps the nearest reminders.
    public static let maximumPendingRequests = 56

    public static func plan(
        vehicle: Vehicle,
        evaluations: [ScheduleEvaluation],
        planItems: [MaintenancePlanItem],
        settings: ReminderSettings,
        lastOdometerUpdate: Date?,
        now: Date,
        calendar: Calendar
    ) -> [ReminderRequest] {
        guard settings.remindersEnabled else { return [] }

        let itemsByID = Dictionary(planItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var requests: [ReminderRequest] = []

        for evaluation in evaluations {
            guard let item = itemsByID[evaluation.planItemID] else { continue }
            guard item.isEnabled, item.reminder.isEnabled else { continue }

            // A snooze pauses reminders without changing the due state. The
            // reminder moves to the end of the snooze, never earlier.
            let earliest = max(now, item.snoozedUntil ?? now)

            if let dueDate = evaluation.nextDueDate,
               let fire = fireDate(
                   forDeadline: dueDate,
                   reminder: item.reminder,
                   earliest: earliest,
                   now: now,
                   calendar: calendar
               ) {
                requests.append(
                    ReminderRequest(
                        id: ReminderRequest.identifier(planItemID: item.id, kind: .calendarDeadline),
                        vehicleID: vehicle.id,
                        planItemID: item.id,
                        kind: .calendarDeadline,
                        fireDate: fire,
                        title: "\(item.title) — \(vehicle.displayName)",
                        body: deadlineBody(evaluation: evaluation, dueDate: dueDate, calendar: calendar, now: now),
                        deepLink: DeepLink.task(vehicleID: vehicle.id, planItemID: item.id).urlString
                    )
                )
            }

            if settings.includeEstimatedMileageReminders,
               evaluation.nextDueDate == nil,
               let estimated = evaluation.estimatedDueDate,
               let confidence = evaluation.estimateConfidence,
               confidence >= .medium,
               let fire = fireDate(
                   forDeadline: estimated,
                   reminder: item.reminder,
                   earliest: earliest,
                   now: now,
                   calendar: calendar
               ) {
                requests.append(
                    ReminderRequest(
                        id: ReminderRequest.identifier(planItemID: item.id, kind: .estimatedMileage),
                        vehicleID: vehicle.id,
                        planItemID: item.id,
                        kind: .estimatedMileage,
                        fireDate: fire,
                        title: "\(item.title) — \(vehicle.displayName)",
                        body: "Estimated to be due around this time based on how far you usually drive. Update your mileage to confirm.",
                        deepLink: DeepLink.task(vehicleID: vehicle.id, planItemID: item.id).urlString
                    )
                )
            }
        }

        if settings.mileageUpdateRemindersEnabled,
           let fire = mileageUpdateFireDate(
               lastUpdate: lastOdometerUpdate,
               settings: settings,
               now: now,
               calendar: calendar
           ) {
            requests.append(
                ReminderRequest(
                    id: ReminderRequest.mileageIdentifier(vehicleID: vehicle.id),
                    vehicleID: vehicle.id,
                    planItemID: nil,
                    kind: .mileageUpdate,
                    fireDate: fire,
                    title: "Update \(vehicle.displayName) mileage",
                    body: "A current reading keeps your next-due information accurate.",
                    deepLink: DeepLink.updateMileage(vehicleID: vehicle.id).urlString
                )
            )
        }

        return requests
    }

    /// Combines per-vehicle plans, de-duplicates and trims to the platform's
    /// practical limit, keeping the nearest reminders.
    public static func bounded(_ requests: [ReminderRequest]) -> [ReminderRequest] {
        var byIdentifier: [String: ReminderRequest] = [:]
        for request in requests {
            if let existing = byIdentifier[request.id], existing.fireDate <= request.fireDate {
                continue
            }
            byIdentifier[request.id] = request
        }
        return byIdentifier.values
            .sorted { lhs, rhs in
                if lhs.fireDate == rhs.fireDate { return lhs.id < rhs.id }
                return lhs.fireDate < rhs.fireDate
            }
            .prefix(maximumPendingRequests)
            .map { $0 }
    }

    /// Works out the minimal set of changes against what is already scheduled.
    public static func reconcile(
        desired: [ReminderRequest],
        pending: [PendingReminder]
    ) -> ReminderReconciliation {
        let desiredByID = Dictionary(desired.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let pendingByID = Dictionary(pending.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var toSchedule: [ReminderRequest] = []
        var unchanged: [String] = []

        for request in desired {
            if let existing = pendingByID[request.id],
               abs(existing.fireDate.timeIntervalSince(request.fireDate)) < 1 {
                unchanged.append(request.id)
            } else {
                toSchedule.append(request)
            }
        }

        let toCancel = pendingByID.keys.filter { desiredByID[$0] == nil }.sorted()

        return ReminderReconciliation(
            toSchedule: toSchedule.sorted { $0.fireDate < $1.fireDate },
            toCancel: toCancel,
            unchanged: unchanged.sorted()
        )
    }

    // MARK: - Fire dates

    /// The moment a deadline reminder should arrive.
    ///
    /// Built from calendar components rather than by subtracting seconds, so a
    /// daylight-saving change still lands at the owner's chosen local time.
    static func fireDate(
        forDeadline deadline: Date,
        reminder: ReminderPreference,
        earliest: Date,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        let deadlineDay = calendar.startOfDay(for: deadline)
        guard let leadDay = calendar.date(byAdding: .day, value: -reminder.leadDays, to: deadlineDay) else {
            return nil
        }
        guard var fire = DateSupport.time(reminder.hour, reminder.minute, on: leadDay, in: calendar) else {
            return nil
        }

        if fire < earliest {
            // Already past: give one nudge at the next preferred time rather
            // than firing immediately or dropping the reminder entirely.
            guard let nudge = nextPreferredTime(after: earliest, reminder: reminder, calendar: calendar) else {
                return nil
            }
            fire = nudge
        }

        return fire > now ? fire : nil
    }

    static func nextPreferredTime(
        after instant: Date,
        reminder: ReminderPreference,
        calendar: Calendar
    ) -> Date? {
        guard let today = DateSupport.time(reminder.hour, reminder.minute, on: instant, in: calendar) else {
            return nil
        }
        if today > instant { return today }
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: instant)) else {
            return nil
        }
        return DateSupport.time(reminder.hour, reminder.minute, on: tomorrow, in: calendar)
    }

    static func mileageUpdateFireDate(
        lastUpdate: Date?,
        settings: ReminderSettings,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        let anchor = lastUpdate ?? now
        guard let due = calendar.date(byAdding: .day, value: settings.mileageUpdateIntervalDays, to: anchor) else {
            return nil
        }
        let preference = ReminderPreference(
            isEnabled: true,
            leadDays: 0,
            hour: settings.preferredHour,
            minute: settings.preferredMinute
        )
        guard var fire = DateSupport.time(
            settings.preferredHour,
            settings.preferredMinute,
            on: due,
            in: calendar
        ) else {
            return nil
        }
        if fire <= now {
            guard let next = nextPreferredTime(after: now, reminder: preference, calendar: calendar) else {
                return nil
            }
            fire = next
        }
        return fire
    }

    static func deadlineBody(
        evaluation: ScheduleEvaluation,
        dueDate: Date,
        calendar: Calendar,
        now: Date
    ) -> String {
        let days = DateSupport.dayCount(from: now, to: dueDate, in: calendar)
        if days < 0 {
            return "Overdue by \(-days) day\(days == -1 ? "" : "s")."
        }
        if days == 0 { return "Due today." }
        return "Due in \(days) day\(days == 1 ? "" : "s")."
    }
}

/// Deep links used by notifications and, later, by any external entry point.
public enum DeepLink: Hashable, Sendable {
    public static let scheme = "odomind"

    case vehicle(id: UUID)
    case task(vehicleID: UUID, planItemID: UUID)
    case updateMileage(vehicleID: UUID)
    case logService(vehicleID: UUID)

    public var urlString: String {
        switch self {
        case .vehicle(let id):
            return "\(DeepLink.scheme)://vehicle/\(id.uuidString)"
        case .task(let vehicleID, let planItemID):
            return "\(DeepLink.scheme)://vehicle/\(vehicleID.uuidString)/task/\(planItemID.uuidString)"
        case .updateMileage(let vehicleID):
            return "\(DeepLink.scheme)://vehicle/\(vehicleID.uuidString)/mileage"
        case .logService(let vehicleID):
            return "\(DeepLink.scheme)://vehicle/\(vehicleID.uuidString)/log"
        }
    }

    public init?(urlString: String) {
        guard let components = URLComponents(string: urlString),
              components.scheme == DeepLink.scheme,
              components.host == "vehicle" else { return nil }
        let parts = components.path.split(separator: "/").map(String.init)
        guard let first = parts.first, let vehicleID = UUID(uuidString: first) else { return nil }

        if parts.count == 1 {
            self = .vehicle(id: vehicleID)
            return
        }
        switch parts[1] {
        case "task":
            guard parts.count >= 3, let planItemID = UUID(uuidString: parts[2]) else { return nil }
            self = .task(vehicleID: vehicleID, planItemID: planItemID)
        case "mileage":
            self = .updateMileage(vehicleID: vehicleID)
        case "log":
            self = .logService(vehicleID: vehicleID)
        default:
            return nil
        }
    }
}
