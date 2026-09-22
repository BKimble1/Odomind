import SwiftUI
import OdomindCore

/// What the appointment sheet collects.
struct AppointmentDraft: Identifiable, Hashable {
    let id: UUID
    var vehicleID: UUID
    var scheduledOn: Date
    var title: String
    var planItemIDs: Set<UUID>
    var location: String
    var notes: String
    var existingID: UUID?

    init(vehicleID: UUID, scheduledOn: Date) {
        self.id = UUID()
        self.vehicleID = vehicleID
        self.scheduledOn = scheduledOn
        self.title = ""
        self.planItemIDs = []
        self.location = ""
        self.notes = ""
        self.existingID = nil
    }

    init(appointment: Appointment) {
        self.id = appointment.id
        self.vehicleID = appointment.vehicleID
        self.scheduledOn = appointment.scheduledOn
        self.title = appointment.title
        self.planItemIDs = Set(appointment.planItemIDs)
        self.location = appointment.location ?? ""
        self.notes = appointment.notes ?? ""
        self.existingID = appointment.id
    }
}

/// Booking a visit.
///
/// Saving this records an intention, not a completion. Nothing here touches a
/// maintenance interval, and the screen says so — because an app that quietly
/// treated a booking as work done would be wrong in the most expensive
/// direction.
struct AppointmentEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var draft: AppointmentDraft
    @State private var showingDelete = false

    init(draft: AppointmentDraft) {
        _draft = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What is it for", text: $draft.title)
                        .accessibilityIdentifier("appointment.title")
                    DatePicker("Date", selection: $draft.scheduledOn, displayedComponents: .date)
                    TextField("Where (optional)", text: $draft.location)
                } footer: {
                    Text("An appointment is a plan, not a record. Odomind will not treat it as work done, and it does not move any due date.")
                }

                if !planItems.isEmpty {
                    Section("Jobs you expect this to cover") {
                        ForEach(planItems) { item in
                            Button {
                                toggle(item.id)
                            } label: {
                                HStack {
                                    Image(systemName: draft.planItemIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(
                                            draft.planItemIDs.contains(item.id)
                                                ? Theme.Palette.accent : Theme.Palette.secondaryText
                                        )
                                    Text(item.title).foregroundStyle(Theme.Palette.primaryText)
                                    Spacer()
                                    if let evaluation = model.evaluation(planItemID: item.id),
                                       let due = evaluation.nextDueDate,
                                       due < draft.scheduledOn {
                                        // Both facts stay true. The booking
                                        // does not move the deadline and the
                                        // deadline does not invalidate the
                                        // booking.
                                        Text("due \(Format.date(due))")
                                            .font(.caption)
                                            .foregroundStyle(Theme.Colors.caution)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Notes") {
                    TextField("Notes (optional)", text: $draft.notes, axis: .vertical)
                        .lineLimit(1...5)
                }

                if draft.existingID != nil {
                    Section {
                        Button("Delete appointment", role: .destructive) { showingDelete = true }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(LuminousField(strength: 0.5))
            .navigationTitle(draft.existingID == nil ? "New appointment" : "Appointment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("appointment.save")
                }
            }
            .confirmationDialog(
                "Delete this appointment?",
                isPresented: $showingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let id = draft.existingID { model.deleteAppointment(id: id) }
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Any service you recorded stays. Only the booking is removed.")
            }
        }
    }

    private var planItems: [MaintenancePlanItem] {
        model.snapshot.planItems(for: draft.vehicleID)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private func toggle(_ id: UUID) {
        if draft.planItemIDs.contains(id) {
            draft.planItemIDs.remove(id)
        } else {
            draft.planItemIDs.insert(id)
        }
    }

    private func save() {
        let appointment = Appointment(
            id: draft.existingID ?? UUID(),
            vehicleID: draft.vehicleID,
            scheduledOn: draft.scheduledOn,
            title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
            planItemIDs: Array(draft.planItemIDs),
            location: draft.location.isEmpty ? nil : draft.location,
            notes: draft.notes.isEmpty ? nil : draft.notes
        )
        if model.saveAppointment(appointment) != nil { dismiss() }
    }
}
