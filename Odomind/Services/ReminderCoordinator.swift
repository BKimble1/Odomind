import Foundation
import OdomindCore

/// The result of one reconciliation pass, surfaced in Settings so reminders are
/// never a black box.
struct ReminderSyncReport: Sendable, Hashable {
    var scheduled: Int
    var cancelled: Int
    var unchanged: Int
    var failures: [String]
    var authorization: NotificationAuthorization
    var plannedCount: Int
    var wasTruncated: Bool
    var ranAt: Date

    static let never = ReminderSyncReport(
        scheduled: 0,
        cancelled: 0,
        unchanged: 0,
        failures: [],
        authorization: .notDetermined,
        plannedCount: 0,
        wasTruncated: false,
        ranAt: .distantPast
    )
}

/// Keeps the system's pending notifications in step with the maintenance plan.
///
/// Called after every change that can move a due date: a logged service, a new
/// reading, an edited schedule, a snooze, a deleted vehicle. It computes the
/// desired set from scratch and applies the difference, so repeated calls
/// converge instead of stacking duplicates.
struct ReminderCoordinator: Sendable {
    let scheduler: NotificationScheduling

    init(scheduler: NotificationScheduling) {
        self.scheduler = scheduler
    }

    /// Builds the desired reminder set for every vehicle in the snapshot.
    static func plan(
        snapshot: GarageSnapshot,
        evaluationsByVehicle: [UUID: [ScheduleEvaluation]],
        now: Date,
        calendar: Calendar
    ) -> [ReminderRequest] {
        var requests: [ReminderRequest] = []
        for vehicle in snapshot.vehicles where !vehicle.isDemo {
            let items = snapshot.planItems(for: vehicle.id)
            let readings = snapshot.readings(for: vehicle.id)
            requests.append(
                contentsOf: ReminderPlanner.plan(
                    vehicle: vehicle,
                    evaluations: evaluationsByVehicle[vehicle.id] ?? [],
                    planItems: items,
                    settings: snapshot.settings.reminders,
                    lastOdometerUpdate: readings.map(\.recordedOn).max(),
                    now: now,
                    calendar: calendar
                )
            )
        }
        return requests
    }

    /// Reconciles the system against `desired`.
    ///
    /// When reminders are off, or permission was denied, everything pending is
    /// cancelled — leaving stale notifications to fire after the owner turned
    /// the feature off would be worse than useless.
    func synchronize(
        desired: [ReminderRequest],
        remindersEnabled: Bool,
        now: Date
    ) async -> ReminderSyncReport {
        let authorization = await scheduler.authorizationStatus()

        guard remindersEnabled, authorization.allowsScheduling else {
            let pending = await scheduler.pending()
            await scheduler.cancel(identifiers: pending.map(\.id))
            return ReminderSyncReport(
                scheduled: 0,
                cancelled: pending.count,
                unchanged: 0,
                failures: [],
                authorization: authorization,
                plannedCount: desired.count,
                wasTruncated: false,
                ranAt: now
            )
        }

        let bounded = ReminderPlanner.bounded(desired.filter { $0.fireDate > now })
        let pending = await scheduler.pending()
        let reconciliation = ReminderPlanner.reconcile(desired: bounded, pending: pending)

        await scheduler.cancel(identifiers: reconciliation.toCancel)
        let failures = await scheduler.schedule(reconciliation.toSchedule)

        return ReminderSyncReport(
            scheduled: reconciliation.toSchedule.count - failures.count,
            cancelled: reconciliation.toCancel.count,
            unchanged: reconciliation.unchanged.count,
            failures: failures.map { "\($0.key): \($0.value)" }.sorted(),
            authorization: authorization,
            plannedCount: desired.count,
            wasTruncated: bounded.count < desired.filter { $0.fireDate > now }.count,
            ranAt: now
        )
    }

    /// Removes every reminder for one vehicle, used when it is deleted.
    func cancelReminders(forPlanItemIDs ids: [UUID]) async {
        var identifiers: [String] = []
        for id in ids {
            for kind in ReminderKind.allCases {
                identifiers.append(ReminderRequest.identifier(planItemID: id, kind: kind))
            }
        }
        await scheduler.cancel(identifiers: identifiers)
    }

    func cancelMileageReminder(vehicleID: UUID) async {
        await scheduler.cancel(identifiers: [ReminderRequest.mileageIdentifier(vehicleID: vehicleID)])
    }
}
