import SwiftUI
import OdomindCore

/// Picks what Odomind should track, and asks what the owner knows about each.
///
/// The history question is the one that matters most: without it, an app either
/// pretends everything was just done or shows everything as overdue. Odomind
/// asks, accepts "I don't know", and keeps that answer visible.
struct TaskSelectionStep: View {
    @Environment(AppModel.self) private var model
    @Binding var draft: VehicleDraft

    @State private var showAdvanced = false
    @State private var didPreselect = false

    private var previewVehicle: Vehicle {
        Vehicle(
            nickname: draft.nickname.isEmpty ? nil : draft.nickname,
            identity: draft.identity,
            configuration: draft.configuration,
            displayUnit: draft.displayUnit,
            inServiceOn: draft.inServiceOn
        )
    }

    private var suggestions: [SuggestedTask] {
        model.allSuggestions(for: previewVehicle)
    }

    var body: some View {
        List {
            Section {
                InlineNotice(
                    message: "Pick what you care about. You can add or remove anything later, and nothing here is permanent."
                )
                Toggle("Show advanced tasks", isOn: $showAdvanced)
            }

            ForEach(byCategory) { group in
                Section {
                    ForEach(group.items) { suggestion in
                        TaskChoiceRow(
                            suggestion: suggestion,
                            isSelected: draft.selectedTaskIDs.contains(suggestion.definition.id),
                            baseline: draft.baselines[suggestion.definition.id] ?? .notProvided,
                            unit: draft.displayUnit,
                            toggle: { toggle(suggestion) },
                            setBaseline: { draft.baselines[suggestion.definition.id] = $0 }
                        )
                    }
                } header: {
                    Label(group.category.displayName, systemImage: group.category.symbolName)
                }
            }
        }
        .listStyle(.insetGrouped)
        .onAppear(perform: preselect)
    }

    private var byCategory: [SuggestionCategoryGroup] {
        let visible = suggestions.filter { showAdvanced || !$0.definition.isAdvanced }
        var buckets: [MaintenanceCategory: [SuggestedTask]] = [:]
        for suggestion in visible {
            buckets[suggestion.definition.category, default: []].append(suggestion)
        }
        return MaintenanceCategory.allCases.compactMap { category in
            guard let items = buckets[category], !items.isEmpty else { return nil }
            return SuggestionCategoryGroup(
                category: category,
                items: items.sorted { $0.definition.title < $1.definition.title }
            )
        }
    }

    private func preselect() {
        guard !didPreselect else { return }
        didPreselect = true
        guard draft.selectedTaskIDs.isEmpty else { return }
        draft.selectedTaskIDs = Set(
            suggestions.filter(\.isRecommendedByDefault).map(\.definition.id)
        )
    }

    private func toggle(_ suggestion: SuggestedTask) {
        let id = suggestion.definition.id
        if draft.selectedTaskIDs.contains(id) {
            draft.selectedTaskIDs.remove(id)
        } else {
            draft.selectedTaskIDs.insert(id)
        }
    }
}

private struct TaskChoiceRow: View {
    let suggestion: SuggestedTask
    let isSelected: Bool
    let baseline: HistoryBaseline
    let unit: DistanceUnit
    let toggle: () -> Void
    let setBaseline: (HistoryBaseline) -> Void

    @State private var showingBaselineEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            Button(action: toggle) {
                HStack(alignment: .top, spacing: Theme.Spacing.medium) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.definition.title)
                            .foregroundStyle(.primary)
                        if let rule = suggestion.rule {
                            Text(rule.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("You supply the interval from your manual")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
            }
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])

            if isSelected {
                HStack(spacing: Theme.Spacing.small) {
                    Text(baselineLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Change") { showingBaselineEditor = true }
                        .font(.caption)
                }
            }

            if case .needsConfirmation(_, let reason) = suggestion.applicability {
                InlineNotice(kind: .caution, message: reason)
            }
        }
        .padding(.vertical, 2)
        .sheet(isPresented: $showingBaselineEditor) {
            BaselineEditor(
                title: suggestion.definition.title,
                unit: unit,
                baseline: baseline,
                onSave: setBaseline
            )
        }
    }

    private var baselineLabel: String {
        switch baseline {
        case .notProvided:
            return "Last done: not answered"
        case .unknownToOwner:
            return "Last done: you don't know"
        case .declared(let date, let odometer):
            var parts: [String] = []
            if let date { parts.append(Format.date(date)) }
            if let odometer { parts.append(Format.distance(odometer)) }
            return parts.isEmpty ? "Last done: starting point set" : "Last done: \(parts.joined(separator: " · "))"
        }
    }
}

/// The "when was this last done?" question, with "I don't know" as a real
/// answer rather than a way out.
struct BaselineEditor: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let unit: DistanceUnit
    let baseline: HistoryBaseline
    let onSave: (HistoryBaseline) -> Void

    @State private var mode: Mode = .unknown
    @State private var date = Date()
    @State private var odometerText = ""
    @State private var didLoad = false

    enum Mode: String, CaseIterable, Identifiable {
        case unknown
        case known
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("", selection: $mode) {
                        Text("I don't know").tag(Mode.unknown)
                        Text("I know roughly").tag(Mode.known)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                } footer: {
                    Text(mode == .unknown
                         ? "Odomind keeps this task separate from your scheduled work instead of pretending it was just done or calling it overdue."
                         : "Give whatever you have. A date alone, a reading alone, or both.")
                }

                if mode == .known {
                    Section {
                        DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                        HStack {
                            TextField("Odometer at the time", text: $odometerText)
                                .keyboardType(.numberPad)
                            Text(unit.abbreviation).foregroundStyle(.secondary)
                        }
                    } footer: {
                        Text("This is a starting point, not a service record. Odomind will not claim work was done.")
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        if case .declared(let existingDate, let odometer) = baseline {
            mode = .known
            if let existingDate { date = existingDate }
            if let odometer { odometerText = String(odometer.amount) }
        } else if case .unknownToOwner = baseline {
            mode = .unknown
        }
    }

    private func save() {
        switch mode {
        case .unknown:
            onSave(.unknownToOwner)
        case .known:
            let amount = Int(odometerText.filter(\.isNumber))
            onSave(.declared(date: date, odometer: amount.map { Distance($0, unit) }))
        }
        dismiss()
    }
}
