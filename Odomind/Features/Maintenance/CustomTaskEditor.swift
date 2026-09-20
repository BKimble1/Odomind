import SwiftUI
import OdomindCore

/// Creates a task the catalog does not cover.
///
/// Custom tasks are never touched by a catalog update and are namespaced so they
/// cannot collide with a published task id.
struct CustomTaskEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var purpose = ""
    @State private var category: MaintenanceCategory = .other
    @State private var action: ServiceAction = .replace
    @State private var wantsSchedule = true
    @State private var shape: ScheduleShape = .distance
    @State private var distanceText = ""
    @State private var timeCount = 6
    @State private var timeUnit: CalendarInterval.Unit = .months

    private var vehicle: Vehicle? { model.selectedVehicle }
    private var unit: DistanceUnit { vehicle?.displayUnit ?? .miles }

    private var rule: ScheduleRule? {
        guard wantsSchedule else { return nil }
        let distance = Int(distanceText.filter(\.isNumber)).flatMap { $0 > 0 ? Distance($0, unit) : nil }
        let time = timeCount > 0 ? CalendarInterval(count: timeCount, unit: timeUnit) : nil
        switch shape {
        case .distance:
            return distance.map { ScheduleRule.distance(interval: $0) }
        case .time:
            return time.map { ScheduleRule.time(interval: $0) }
        case .distanceOrTime:
            guard let distance, let time else { return nil }
            return .distanceOrTime(distance: distance, time: time)
        case .conditionCheck:
            guard distance != nil || time != nil else { return nil }
            return .conditionCheck(every: RecurrenceBasis(distance: distance, time: time))
        case .oneTime:
            guard distance != nil || time != nil else { return nil }
            return .oneTime(atDistance: distance, atAge: time)
        case .fixedMilestones:
            guard let distance else { return nil }
            return .fixedMilestones(
                FixedMilestoneSchedule(distanceMilestones: [distance], repeatEvery: distance)
            )
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (!wantsSchedule || rule != nil)
            && vehicle != nil
    }

    var body: some View {
        Form {
            Section("Task") {
                TextField("Name", text: $title)
                TextField("What it is for (optional)", text: $purpose, axis: .vertical)
                    .lineLimit(1...4)
                Picker("Category", selection: $category) {
                    ForEach(MaintenanceCategory.allCases, id: \.self) { value in
                        Label(value.displayName, systemImage: value.symbolName).tag(value)
                    }
                }
                Picker("Action", selection: $action) {
                    ForEach(ServiceAction.allCases, id: \.self) { value in
                        Text(value.verb).tag(value)
                    }
                }
            }

            Section {
                Toggle("Give it a schedule", isOn: $wantsSchedule)
            } footer: {
                Text("Without a schedule the task still appears, and you can log it whenever you do the work. Odomind just will not tell you when it is next due.")
            }

            if wantsSchedule {
                Section("Schedule") {
                    Picker("Type", selection: $shape) {
                        ForEach(ScheduleShape.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    if shape != .time {
                        HStack {
                            TextField("Distance", text: $distanceText)
                                .keyboardType(.numberPad)
                            Text(unit.abbreviation).foregroundStyle(.secondary)
                        }
                    }
                    if shape != .distance, shape != .fixedMilestones {
                        Stepper("\(timeCount)", value: $timeCount, in: 0...120)
                        Picker("Unit", selection: $timeUnit) {
                            Text("days").tag(CalendarInterval.Unit.days)
                            Text("weeks").tag(CalendarInterval.Unit.weeks)
                            Text("months").tag(CalendarInterval.Unit.months)
                            Text("years").tag(CalendarInterval.Unit.years)
                        }
                        .pickerStyle(.segmented)
                    }
                    if let rule {
                        Text(rule.summary)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Custom task")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    guard let vehicle else { return }
                    if model.addCustomTask(
                        to: vehicle,
                        title: title,
                        purpose: purpose,
                        category: category,
                        action: action,
                        rule: rule
                    ) != nil {
                        dismiss()
                    }
                }
                .disabled(!canSave)
            }
        }
    }
}
