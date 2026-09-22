import SwiftUI
import OdomindCore

/// Which job (or jobs) a quick log is about.
struct QuickLogRequest: Identifiable, Hashable {
    let id = UUID()
    var vehicleID: UUID
    /// The job the checkmark was tapped on. Others can be added in the sheet.
    var planItemID: UUID
}

/// The short sheet a checkmark opens.
///
/// A tick never records work on its own. Two things have to be said before a
/// completion means anything — when it happened and at what mileage — and
/// guessing either of them corrupts every future due date. So this asks, with
/// today already filled in and the last known reading shown for what it is.
///
/// More than one job can be ticked, because a visit is usually more than one
/// job, and one visit should be one record.
struct QuickLogSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let request: QuickLogRequest

    @State private var selected: Set<UUID> = []
    @State private var performedOn = Date()
    @State private var odometerText = ""
    @State private var isShop = false
    @State private var shopName = ""
    @State private var costText = ""
    @State private var notes = ""
    @State private var isSaving = false
    @State private var didPrepare = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(candidates) { item in
                        Button {
                            toggle(item.id)
                        } label: {
                            HStack {
                                Image(systemName: selected.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(
                                        selected.contains(item.id) ? Theme.Palette.accent : Theme.Palette.secondaryText
                                    )
                                Text(item.title)
                                    .foregroundStyle(Theme.Palette.primaryText)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected.contains(item.id) ? [.isButton, .isSelected] : .isButton)
                        .accessibilityIdentifier("quickLog.item.\(item.definitionID)")
                    }
                } header: {
                    Text("What was done")
                } footer: {
                    Text("Tick everything done in the same visit and Odomind records it as one.")
                }

                Section("When") {
                    DatePicker("Date", selection: $performedOn, in: ...Date(), displayedComponents: .date)
                        .accessibilityIdentifier("quickLog.date")
                }

                Section {
                    HStack {
                        TextField("Mileage", text: $odometerText)
                            .keyboardType(.numberPad)
                            .accessibilityIdentifier("quickLog.odometer")
                        if let vehicle { Text(vehicle.displayUnit.abbreviation).foregroundStyle(.secondary) }
                    }
                } header: {
                    Text("Mileage")
                } footer: {
                    // Never presented as today's measurement. The last reading
                    // is shown with the date it was taken, and left out of the
                    // field, so nothing is recorded that nobody read.
                    Text(mileageFooter)
                }

                Section("Who") {
                    Picker("Done by", selection: $isShop) {
                        Text("Me").tag(false)
                        Text("A shop").tag(true)
                    }
                    .pickerStyle(.segmented)
                    if isShop {
                        TextField("Shop name (optional)", text: $shopName)
                    }
                    HStack {
                        TextField("Total cost (optional)", text: $costText)
                            .keyboardType(.decimalPad)
                        Text(Locale.current.currency?.identifier ?? "USD")
                            .foregroundStyle(.secondary)
                    }
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .scrollContentBackground(.hidden)
            .background(LuminousField(strength: 0.5))
            .navigationTitle("Record work")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(selected.isEmpty || isSaving)
                        .accessibilityIdentifier("quickLog.save")
                }
            }
            .onAppear(perform: prepare)
        }
        .presentationDetents([.medium, .large])
    }

    private var vehicle: Vehicle? { model.snapshot.vehicle(id: request.vehicleID) }

    /// The tapped job first, then everything else due around now — the jobs
    /// most likely to have happened in the same visit.
    private var candidates: [MaintenancePlanItem] {
        let items = model.snapshot.planItems(for: request.vehicleID)
        guard let tapped = items.first(where: { $0.id == request.planItemID }) else { return items }
        let states = Dictionary(
            model.evaluations(for: request.vehicleID).map { ($0.planItemID, $0.state) },
            uniquingKeysWith: { first, _ in first }
        )
        let others = items
            .filter { $0.id != tapped.id }
            .filter { states[$0.id] == .overdue || states[$0.id] == .dueSoon }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        return [tapped] + others
    }

    private var mileageFooter: String {
        guard let vehicle, let reading = model.latestReading(for: vehicle.id) else {
            return "Leave this blank if you did not note it. Odomind will not invent a reading."
        }
        return "Last recorded: \(Format.distance(reading.value)) on \(Format.date(reading.recordedOn)). Enter today's reading if you have it, or leave this blank."
    }

    private func prepare() {
        guard !didPrepare else { return }
        didPrepare = true
        selected = [request.planItemID]
        performedOn = model.clock.now
    }

    private func toggle(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func save() {
        // Guards against a second tap landing while the first is in flight.
        guard !isSaving else { return }
        isSaving = true

        let performer: ServicePerformer = isShop
            ? .shop(name: shopName.trimmingCharacters(in: .whitespacesAndNewlines))
            : .doItYourself

        let saved = model.quickLog(
            vehicleID: request.vehicleID,
            planItemIDs: selected,
            performedOn: performedOn,
            odometerAmount: Int(odometerText.filter(\.isNumber)),
            performer: performer,
            totalCostText: costText,
            notes: notes
        )

        if saved != nil {
            dismiss()
        } else {
            // `saveService` has already put the reason on screen; the sheet
            // stays open with the owner's entry intact.
            isSaving = false
        }
    }
}

/// One search hit in the Jobs or Home list.
struct JobSearchRow: View {
    let result: JobSearchResult
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: Theme.Spacing.medium) {
                Image(systemName: result.category.symbolName)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .frame(width: 22)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title)
                        .font(.body)
                        .foregroundStyle(Theme.Palette.primaryText)
                        .multilineTextAlignment(.leading)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.secondaryText)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: Theme.Spacing.small)
                if !result.isTracked {
                    // Says what tapping does, rather than offering a second
                    // copy of something already tracked.
                    Text("Add")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.Palette.accent)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Theme.Spacing.medium)
            .padding(.vertical, Theme.Spacing.medium)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("jobSearch.\(result.definitionID)")
    }

    private var subtitle: String {
        if let state = result.state { return "\(result.category.displayName) · \(state.displayName)" }
        return "\(result.category.displayName) · not tracked yet"
    }
}
