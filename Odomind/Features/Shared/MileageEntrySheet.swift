import SwiftUI
import OdomindCore

/// Updating mileage is the single most common thing an owner does here, so it
/// is one screen, one field, and the keyboard is already up.
struct MileageEntrySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let vehicle: Vehicle

    @State private var text = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var showingReplacement = false
    @FocusState private var fieldIsFocused: Bool

    private var amount: Int? {
        let cleaned = text.filter(\.isNumber)
        guard !cleaned.isEmpty else { return nil }
        return Int(cleaned)
    }

    private var issues: [OdometerIssue] {
        guard let amount else { return [] }
        return model.odometerIssues(for: vehicle, proposedAmount: amount, on: date)
    }

    private var blockingIssues: [OdometerIssue] { issues.filter(\.isBlocking) }
    private var warnings: [OdometerIssue] { issues.filter { !$0.isBlocking } }

    private var decreased: Bool {
        issues.contains { if case .decreasedFromEarlier = $0 { return true }; return false }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Odometer", text: $text)
                            .keyboardType(.numberPad)
                            .font(.system(.title2, design: .rounded))
                            .monospacedDigit()
                            .focused($fieldIsFocused)
                            .accessibilityIdentifier("mileage.field")
                            .accessibilityLabel(Text("Odometer reading in \(vehicle.displayUnit.localizedName)"))
                        Text(vehicle.displayUnit.abbreviation)
                            .foregroundStyle(.secondary)
                    }
                    DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                } header: {
                    Text("Reading")
                } footer: {
                    if let previous = model.latestReading(for: vehicle.id) {
                        Text("Last recorded: \(Format.distance(previous.value)) on \(Format.date(previous.recordedOn)).")
                    } else {
                        Text("Read this off your dashboard. Odomind cannot see it.")
                    }
                }

                if !blockingIssues.isEmpty {
                    Section {
                        ForEach(Array(blockingIssues.enumerated()), id: \.offset) { _, issue in
                            InlineNotice(kind: .caution, message: message(for: issue))
                        }
                    }
                }

                if !warnings.isEmpty {
                    Section {
                        ForEach(Array(warnings.enumerated()), id: \.offset) { _, issue in
                            InlineNotice(kind: .caution, message: message(for: issue))
                        }
                        if decreased {
                            Button("My odometer was replaced") {
                                showingReplacement = true
                            }
                            .accessibilityHint(Text("Record an instrument cluster replacement so earlier mileage is kept."))
                        }
                    } header: {
                        Text("Check this")
                    } footer: {
                        Text("Odomind will not guess between a typo and a replaced odometer. Correct the number, or record a replacement.")
                    }
                }

                Section {
                    TextField("Note (optional)", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                }
            }
            .scrollContentBackground(.hidden)
            .background(LuminousField(strength: 0.5))
            .navigationTitle("Update mileage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(amount == nil || !blockingIssues.isEmpty)
                        .accessibilityIdentifier("mileage.save")
                }
            }
            .sheet(isPresented: $showingReplacement) {
                OdometerReplacementSheet(vehicle: vehicle, suggestedNewReading: amount)
            }
            .onAppear { fieldIsFocused = true }
        }
    }

    private func save() {
        guard let amount else { return }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if model.recordOdometer(
            vehicleID: vehicle.id,
            amount: amount,
            on: date,
            note: trimmedNote.isEmpty ? nil : trimmedNote
        ) {
            dismiss()
        }
    }

    private func message(for issue: OdometerIssue) -> String {
        switch issue {
        case .futureDated:
            return "That date is in the future. Pick today or earlier."
        case .negativeValue:
            return "An odometer reading cannot be negative."
        case .implausiblyLarge(let distance):
            return "\(Format.distance(distance)) is higher than any vehicle Odomind expects. Check the digits."
        case .duplicateOfExisting(let existing, let date):
            return "You already recorded \(Format.distance(existing)) on \(Format.date(date)). Saving again will add a duplicate."
        case .decreasedFromEarlier(let earlier, let date):
            return "This is lower than \(Format.distance(earlier)) recorded on \(Format.date(date))."
        case .implausibleIncrease(let perDay, let unit):
            return "That works out to about \(perDay.formatted()) \(unit.localizedName) a day. Check for an extra digit."
        }
    }
}

/// The explicit odometer-replacement workflow.
///
/// Recording one here keeps every earlier reading and every past service on the
/// same cumulative scale, so a cluster swap does not quietly reset the
/// maintenance schedule.
struct OdometerReplacementSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let vehicle: Vehicle
    var suggestedNewReading: Int?

    @State private var previousText = ""
    @State private var newText = ""
    @State private var date = Date()
    @State private var note = ""

    private var previousAmount: Int? { Int(previousText.filter(\.isNumber)) }
    private var newAmount: Int? { Int(newText.filter(\.isNumber)) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Final reading on the old unit") {
                        TextField("0", text: $previousText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Reading on the new unit") {
                        TextField("0", text: $newText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    DatePicker("Replaced on", selection: $date, in: ...Date(), displayedComponents: .date)
                } header: {
                    Text("Odometer replacement")
                } footer: {
                    Text("Odomind keeps counting from where the old unit stopped. The dashboard shows the new one.")
                }

                if let previousAmount, let newAmount {
                    Section("What this means") {
                        ValueRow(
                            label: "Distance carried forward",
                            value: Format.distance(Distance(previousAmount - newAmount, vehicle.displayUnit))
                        )
                    }
                }

                Section {
                    TextField("Note (optional)", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                }
            }
            .scrollContentBackground(.hidden)
            .background(LuminousField(strength: 0.5))
            .navigationTitle("Odometer replaced")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(previousAmount == nil || newAmount == nil)
                }
            }
            .onAppear {
                if previousText.isEmpty, let latest = model.latestReading(for: vehicle.id) {
                    previousText = String(latest.value.amount)
                }
                if newText.isEmpty, let suggestedNewReading {
                    newText = String(suggestedNewReading)
                }
            }
        }
    }

    private func save() {
        guard let previousAmount, let newAmount else { return }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        model.recordOdometerReplacement(
            vehicleID: vehicle.id,
            occurredOn: date,
            previousFinalReading: previousAmount,
            newStartReading: newAmount,
            note: trimmed.isEmpty ? nil : trimmed
        )
        dismiss()
    }
}
