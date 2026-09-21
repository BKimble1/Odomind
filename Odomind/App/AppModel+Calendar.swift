import Foundation
import OdomindCore

/// One thing on one day.
///
/// Four kinds, kept apart because they mean four different things and running
/// them together is how a calendar starts claiming work happened.
enum CalendarEntryKind: String, Hashable, CaseIterable {
    /// Work the owner recorded. It happened.
    case completed
    /// A booking. It has not happened.
    case appointment
    /// A deadline Odomind can stand behind: a date rule, or a distance rule
    /// the owner's own reading has already reached.
    case due
    /// A date worked out from how far the owner usually drives. A guess, and
    /// labelled as one everywhere it appears.
    case projected

    var displayName: String {
        switch self {
        case .completed: return "Done"
        case .appointment: return "Appointment"
        case .due: return "Due"
        case .projected: return "Estimated"
        }
    }

    var symbolName: String {
        switch self {
        case .completed: return "checkmark.circle.fill"
        case .appointment: return "calendar.badge.clock"
        case .due: return "exclamationmark.circle"
        case .projected: return "chart.line.uptrend.xyaxis"
        }
    }
}

struct CalendarEntry: Identifiable, Hashable {
    var id: String
    var date: Date
    var kind: CalendarEntryKind
    var title: String
    var subtitle: String?
    var vehicleID: UUID
    var planItemID: UUID?
    var recordID: UUID?
    var appointmentID: UUID?
}

extension AppModel {

    /// How far ahead the calendar projects.
    ///
    /// Bounded on purpose. A mileage-based job's date moves every time a
    /// reading is added, so an endless series of them would be a calendar full
    /// of dates that are wrong by next month.
    var calendarProjectionMonths: Int { preferences.calendar.projectionMonths }

    /// Which vehicles the calendar is showing. The sample never appears
    /// unless it is the one selected.
    private var calendarVehicles: [Vehicle] {
        guard let selected = selectedVehicle else { return [] }
        return [selected]
    }

    /// Everything on one day, in a stable order.
    func calendarEntries(on day: Date) -> [CalendarEntry] {
        let start = calendar.startOfDay(for: day)
        return allCalendarEntries().filter { calendar.isDate($0.date, inSameDayAs: start) }
    }

    /// Every entry inside the projection window, plus all recorded history.
    ///
    /// History is not windowed: the owner's own records are facts and belong
    /// in the calendar wherever they fall.
    func allCalendarEntries() -> [CalendarEntry] {
        var entries: [CalendarEntry] = []
        let now = clock.now
        let horizon = calendar.date(byAdding: .month, value: calendarProjectionMonths, to: now) ?? now

        for vehicle in calendarVehicles {
            for record in serviceRecords(for: vehicle.id) {
                entries.append(
                    CalendarEntry(
                        id: "record.\(record.id)",
                        date: calendar.startOfDay(for: record.performedOn),
                        kind: .completed,
                        title: record.title,
                        subtitle: record.odometer.map { Format.distance($0) },
                        vehicleID: vehicle.id,
                        recordID: record.id
                    )
                )
            }

            for appointment in snapshot.appointments(for: vehicle.id) {
                entries.append(
                    CalendarEntry(
                        id: "appointment.\(appointment.id)",
                        date: calendar.startOfDay(for: appointment.scheduledOn),
                        kind: .appointment,
                        title: appointment.title,
                        subtitle: appointment.location,
                        vehicleID: vehicle.id,
                        appointmentID: appointment.id
                    )
                )
            }

            for evaluation in evaluations(for: vehicle.id) {
                guard evaluation.state.isScheduled else { continue }
                // A confirmed deadline beats an estimate for the same job: one
                // job, one date, and never both on the calendar at once.
                if let due = evaluation.nextDueDate {
                    guard due <= horizon else { continue }
                    entries.append(
                        CalendarEntry(
                            id: "due.\(evaluation.planItemID)",
                            date: calendar.startOfDay(for: due),
                            kind: .due,
                            title: evaluation.title,
                            subtitle: evaluation.nextDueOdometer.map { "at \(Format.distance($0))" },
                            vehicleID: vehicle.id,
                            planItemID: evaluation.planItemID
                        )
                    )
                } else if let estimated = evaluation.estimatedDueDate {
                    guard estimated <= horizon else { continue }
                    entries.append(
                        CalendarEntry(
                            id: "projected.\(evaluation.planItemID)",
                            date: calendar.startOfDay(for: estimated),
                            kind: .projected,
                            title: evaluation.title,
                            subtitle: evaluation.nextDueOdometer.map { "around \(Format.distance($0))" },
                            vehicleID: vehicle.id,
                            planItemID: evaluation.planItemID
                        )
                    )
                }
            }
        }

        return entries.sorted { left, right in
            if left.date != right.date { return left.date < right.date }
            if left.kind != right.kind { return kindRank(left.kind) < kindRank(right.kind) }
            return left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
        }
    }

    private func kindRank(_ kind: CalendarEntryKind) -> Int {
        switch kind {
        case .appointment: return 0
        case .due: return 1
        case .projected: return 2
        case .completed: return 3
        }
    }

    /// Scheduled jobs Odomind cannot put on a day.
    ///
    /// A distance-based job with no usable driving estimate has no defensible
    /// date, so it goes in a list rather than on an invented square. This is
    /// the honest alternative to spreading them evenly across next month.
    func unscheduledCalendarItems() -> [ScheduleEvaluation] {
        calendarVehicles.flatMap { vehicle in
            evaluations(for: vehicle.id).filter { evaluation in
                evaluation.state.isScheduled
                    && evaluation.nextDueDate == nil
                    && evaluation.estimatedDueDate == nil
            }
        }
        .sorted { $0.urgencyKey < $1.urgencyKey }
    }

    // MARK: - Appointments

    @discardableResult
    func saveAppointment(_ appointment: Appointment) -> UUID? {
        do {
            var stored = appointment
            stored.scheduledOn = calendar.startOfDay(for: appointment.scheduledOn)
            try store.save(appointment: stored)
            refresh()
            return stored.id
        } catch {
            alert = .saveFailed(error)
            return nil
        }
    }

    func deleteAppointment(id: UUID) {
        do {
            try store.deleteAppointment(id: id)
            refresh()
        } catch {
            alert = .saveFailed(error)
        }
    }
}
