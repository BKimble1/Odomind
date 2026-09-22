import SwiftUI
import OdomindCore

/// The schedule shapes the owner can choose from when writing their own.
///
/// Declared at file scope and not called `Shape`, which is a SwiftUI
/// protocol and would read confusingly inside a view.
enum ScheduleShape: String, CaseIterable, Identifiable {
    case distance
    case time
    case distanceOrTime
    case fixedMilestones
    case conditionCheck
    case oneTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .distance: return "Every set distance"
        case .time: return "Every set time"
        case .distanceOrTime: return "Distance or time, whichever first"
        case .fixedMilestones: return "At odometer milestones"
        case .conditionCheck: return "Periodic check"
        case .oneTime: return "Once"
        }
    }

    var explanation: String {
        switch self {
        case .distance:
            return "Counts from the last time you logged this job."
        case .time:
            return "Counts from the last time you logged this job."
        case .distanceOrTime:
            return "Whichever arrives first after the last time you logged it."
        case .fixedMilestones:
            return "Counted off the odometer, not off the last service. Doing the work early does not move the next milestone."
        case .conditionCheck:
            return "Schedules a look, not a replacement. Use this where the answer is 'replace it when it is worn'."
        case .oneTime:
            return "Happens once and then stops."
        }
    }
}

/// Lets the owner write the schedule for one task.
///
/// This is the manual workflow that makes a task without a published interval
/// genuinely useful: open the manual, type in what it says, and Odomind tracks
/// it from there. The result is stored as the owner's own rule, which no
/// catalog update can overwrite.
struct ScheduleEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let planItemID: UUID

    @State private var shape: ScheduleShape = .distance
    @State private var distanceText = ""
    @State private var timeCount = 6
    @State private var timeUnit: CalendarInterval.Unit = .months
    @State private var milestoneText = ""
    @State private var repeatText = ""
    @State private var didLoad = false

    private var item: MaintenancePlanItem? { model.planItem(id: planItemID) }
    private var vehicle: Vehicle? { item.flatMap { model.snapshot.vehicle(id: $0.vehicleID) } }
    private var unit: DistanceUnit { vehicle?.displayUnit ?? .miles }

    private var distanceAmount: Int? {
        let cleaned = distanceText.filter(\.isNumber)
        return cleaned.isEmpty ? nil : Int(cleaned)
    }

    private var proposedRule: ScheduleRule? {
        switch shape {
        case .distance:
            guard let distanceAmount, distanceAmount > 0 else { return nil }
            return .distance(interval: Distance(distanceAmount, unit))
        case .time:
            guard timeCount > 0 else { return nil }
            return .time(interval: CalendarInterval(count: timeCount, unit: timeUnit))
        case .distanceOrTime:
            guard let distanceAmount, distanceAmount > 0, timeCount > 0 else { return nil }
            return .distanceOrTime(
                distance: Distance(distanceAmount, unit),
                time: CalendarInterval(count: timeCount, unit: timeUnit)
            )
        case .fixedMilestones:
            let milestones = milestoneText
                .components(separatedBy: CharacterSet(charactersIn: ",; "))
                .compactMap { Int($0.filter(\.isNumber)) }
                .filter { $0 > 0 }
                .map { Distance($0, unit) }
            let repeatEvery = Int(repeatText.filter(\.isNumber)).flatMap { $0 > 0 ? Distance($0, unit) : nil }
            guard !milestones.isEmpty || repeatEvery != nil else { return nil }
            return .fixedMilestones(
                FixedMilestoneSchedule(distanceMilestones: milestones, repeatEvery: repeatEvery)
            )
        case .conditionCheck:
            let distance = distanceAmount.flatMap { $0 > 0 ? Distance($0, unit) : nil }
            let time = timeCount > 0 ? CalendarInterval(count: timeCount, unit: timeUnit) : nil
            guard distance != nil || time != nil else { return nil }
            return .conditionCheck(every: RecurrenceBasis(distance: distance, time: time))
        case .oneTime:
            let distance = distanceAmount.flatMap { $0 > 0 ? Distance($0, unit) : nil }
            let time = timeCount > 0 ? CalendarInterval(count: timeCount, unit: timeUnit) : nil
            guard distance != nil || time != nil else { return nil }
            return .oneTime(atDistance: distance, atAge: time)
        }
    }

    private var problems: [String] { proposedRule?.validationProblems ?? [] }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Schedule type", selection: $shape) {
                        ForEach(ScheduleShape.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    Text(shape.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if usesDistance {
                    Section("Distance") {
                        HStack {
                            TextField(shape == .oneTime ? "At odometer" : "Interval", text: $distanceText)
                                .keyboardType(.numberPad)
                            Text(unit.abbreviation).foregroundStyle(.secondary)
                        }
                    }
                }

                if usesMilestones {
                    Section {
                        TextField("e.g. 30000, 60000, 90000", text: $milestoneText)
                            .keyboardType(.numbersAndPunctuation)
                        HStack {
                            TextField("Then every (optional)", text: $repeatText)
                                .keyboardType(.numberPad)
                            Text(unit.abbreviation).foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Milestones")
                    } footer: {
                        Text("Separate milestones with commas. These are odometer readings, not intervals.")
                    }
                }

                if usesTime {
                    Section(shape == .oneTime ? "Age" : "Time") {
                        Stepper("\(timeCount)", value: $timeCount, in: 0...120)
                        Picker("Unit", selection: $timeUnit) {
                            Text("days").tag(CalendarInterval.Unit.days)
                            Text("weeks").tag(CalendarInterval.Unit.weeks)
                            Text("months").tag(CalendarInterval.Unit.months)
                            Text("years").tag(CalendarInterval.Unit.years)
                        }
                        .pickerStyle(.segmented)
                    }
                }

                if let rule = proposedRule {
                    Section("Preview") {
                        Text(rule.summary)
                            .font(.callout.weight(.medium))
                        if let caveat = rule.caveat {
                            Text(caveat)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if !problems.isEmpty {
                    Section {
                        ForEach(problems, id: \.self) { problem in
                            InlineNotice(kind: .caution, message: problem)
                        }
                    }
                }

                Section {
                    InlineNotice(
                        message: "This becomes your schedule for this vehicle. Odomind will not replace it when the built-in catalog changes."
                    )
                }
            }
            .scrollContentBackground(.hidden)
            .background(LuminousField(strength: 0.5))
            .navigationTitle("Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let rule = proposedRule else { return }
                        model.setOwnerRule(rule, planItemID: planItemID)
                        dismiss()
                    }
                    .disabled(proposedRule == nil || !problems.isEmpty)
                }
            }
            .onAppear(perform: loadExisting)
        }
    }

    private var usesDistance: Bool {
        switch shape {
        case .distance, .distanceOrTime, .conditionCheck, .oneTime: return true
        case .time, .fixedMilestones: return false
        }
    }

    private var usesMilestones: Bool { shape == .fixedMilestones }

    private var usesTime: Bool {
        switch shape {
        case .time, .distanceOrTime, .conditionCheck, .oneTime: return true
        case .distance, .fixedMilestones: return false
        }
    }

    /// Pre-fills from whatever schedule is already in force, so editing is a
    /// tweak rather than a retype.
    private func loadExisting() {
        guard !didLoad, let rule = item?.effectiveRule else {
            didLoad = true
            return
        }
        didLoad = true
        switch rule {
        case .distance(let interval):
            shape = .distance
            distanceText = String(interval.converted(to: unit).amount)
        case .time(let interval):
            shape = .time
            timeCount = interval.count
            timeUnit = interval.unit
        case .distanceOrTime(let distance, let time):
            shape = .distanceOrTime
            distanceText = String(distance.converted(to: unit).amount)
            timeCount = time.count
            timeUnit = time.unit
        case .fixedMilestones(let schedule):
            shape = .fixedMilestones
            milestoneText = schedule.sortedDistanceMilestones
                .map { String($0.converted(to: unit).amount) }
                .joined(separator: ", ")
            if let repeatEvery = schedule.repeatEvery {
                repeatText = String(repeatEvery.converted(to: unit).amount)
            }
        case .conditionCheck(let basis):
            shape = .conditionCheck
            if let distance = basis.distance { distanceText = String(distance.converted(to: unit).amount) }
            if let time = basis.time {
                timeCount = time.count
                timeUnit = time.unit
            } else {
                timeCount = 0
            }
        case .oneTime(let atDistance, let atAge):
            shape = .oneTime
            if let atDistance { distanceText = String(atDistance.converted(to: unit).amount) }
            if let atAge {
                timeCount = atAge.count
                timeUnit = atAge.unit
            } else {
                timeCount = 0
            }
        case .vehicleIndicator:
            // Indicator schedules come from the catalog and are not editable
            // here; the owner records the message instead.
            shape = .conditionCheck
        }
    }
}
