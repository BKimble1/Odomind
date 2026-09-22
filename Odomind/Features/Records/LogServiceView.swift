import SwiftUI
import PhotosUI
import OdomindCore

/// Records a completed visit.
///
/// One visit, one date, one odometer reading, one total — and as many tasks as
/// were actually done. The total is never multiplied across the tasks, which is
/// what makes the spending figures in History mean anything.
struct LogServiceView: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    let vehicle: Vehicle
    var preselectedPlanItemID: UUID?
    var editingRecord: ServiceRecord?

    @State private var draft: ServiceDraft
    @State private var shopName = ""
    @State private var isShop = false
    @State private var showingExtraTasks = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showingReceiptScan = false
    @State private var odometerText = ""
    @State private var didPrepare = false

    init(vehicle: Vehicle, preselectedPlanItemID: UUID? = nil, editingRecord: ServiceRecord? = nil) {
        self.vehicle = vehicle
        self.preselectedPlanItemID = preselectedPlanItemID
        self.editingRecord = editingRecord
        _draft = State(
            initialValue: ServiceDraft(
                vehicleID: vehicle.id,
                performedOn: editingRecord?.performedOn ?? Date(),
                odometerAmount: editingRecord?.odometer?.amount,
                currencyCode: editingRecord?.totalCost?.currencyCode
                    ?? Locale.current.currency?.identifier
                    ?? "USD",
                editingRecordID: editingRecord?.id
            )
        )
    }

    private var planItems: [MaintenancePlanItem] {
        model.snapshot.planItems(for: vehicle.id).sorted { $0.title.lowercased() < $1.title.lowercased() }
    }

    private var issues: [ServiceRecordIssue] { model.serviceIssues(for: draft) }
    private var blocking: [ServiceRecordIssue] { issues.filter(\.isBlocking) }
    private var warnings: [ServiceRecordIssue] { issues.filter { !$0.isBlocking } }

    var body: some View {
        NavigationStack {
            Form {
                Section("What was done") {
                    if planItems.isEmpty {
                        Text("This vehicle has no tracked tasks yet. Add some in Maintenance, or pick from the catalog below.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(planItems) { item in
                        Button {
                            toggle(item.id)
                        } label: {
                            HStack {
                                Image(systemName: draft.selectedPlanItemIDs.contains(item.id)
                                    ? "checkmark.circle.fill"
                                    : "circle")
                                    .foregroundStyle(draft.selectedPlanItemIDs.contains(item.id) ? Color.accentColor : Color.secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.title).foregroundStyle(.primary)
                                    Text(item.action.verb)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                        .accessibilityIdentifier("logService.task.\(item.definitionID)")
                        .accessibilityAddTraits(draft.selectedPlanItemIDs.contains(item.id) ? [.isSelected] : [])
                    }
                    Button("Something else…") { showingExtraTasks = true }
                        .font(.callout)
                }

                if !draft.extraDefinitionIDs.isEmpty {
                    Section("Also recorded") {
                        ForEach(Array(draft.extraDefinitionIDs).sorted(), id: \.self) { definitionID in
                            HStack {
                                Text(model.catalogService.catalog?.definition(id: definitionID)?.title ?? definitionID)
                                Spacer()
                                Button("Remove") { draft.extraDefinitionIDs.remove(definitionID) }
                                    .font(.caption)
                            }
                        }
                    }
                }

                Section("When") {
                    DatePicker("Date", selection: $draft.performedOn, in: ...Date(), displayedComponents: .date)
                    HStack {
                        TextField("Odometer", text: $odometerText)
                            .keyboardType(.numberPad)
                            .accessibilityIdentifier("logService.odometer")
                            .onChange(of: odometerText) { _, newValue in
                                draft.odometerAmount = Int(newValue.filter(\.isNumber))
                            }
                        Text(vehicle.displayUnit.abbreviation).foregroundStyle(.secondary)
                    }
                }

                Section("Who") {
                    Picker("Performed by", selection: $isShop) {
                        Text("Me").tag(false)
                        Text("A shop").tag(true)
                    }
                    .pickerStyle(.segmented)
                    if isShop {
                        TextField("Shop name", text: $shopName)
                    }
                }

                Section {
                    HStack {
                        TextField("Total cost", text: $draft.totalCostText)
                            .keyboardType(.decimalPad)
                        Text(draft.currencyCode).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Cost")
                } footer: {
                    Text("One total for the whole visit. Odomind counts it once, no matter how many tasks were done.")
                }

                Section("Notes and receipts") {
                    TextField("Notes", text: $draft.notes, axis: .vertical)
                        .lineLimit(1...5)

                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Add a photo or receipt", systemImage: "paperclip")
                    }

                    // Pro, and gated here rather than hidden: somebody who
                    // does not have it should be able to see what it does.
                    Button {
                        if model.isPro {
                            showingReceiptScan = true
                        } else {
                            router.presentPaywall = true
                        }
                    } label: {
                        LabeledContent {
                            if !model.isPro {
                                Text("Pro")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.Palette.accent)
                            }
                        } label: {
                            Label("Scan a receipt", systemImage: "doc.text.viewfinder")
                        }
                    }
                    .accessibilityIdentifier("logService.scanReceipt")

                    ForEach(draft.attachmentIDs, id: \.self) { id in
                        HStack {
                            Image(systemName: "doc")
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            Text(model.snapshot.attachment(id: id).map { Format.byteCount($0.byteCount) } ?? "Attachment")
                            Spacer()
                            Button("Remove") {
                                draft.attachmentIDs.removeAll { $0 == id }
                                model.removeAttachment(id: id, fromRecord: draft.editingRecordID)
                            }
                            .font(.caption)
                        }
                    }
                }

                if !blocking.isEmpty || !warnings.isEmpty {
                    Section("Check this") {
                        ForEach(Array((blocking + warnings).enumerated()), id: \.offset) { _, issue in
                            InlineNotice(kind: issue.isBlocking ? .caution : .information, message: issue.message)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(LuminousField(strength: 0.5))
            .navigationTitle(editingRecord == nil ? "Log service" : "Edit service")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!draft.hasSelection || !blocking.isEmpty)
                        .accessibilityIdentifier("logService.save")
                }
            }
            .sheet(isPresented: $showingReceiptScan) {
                ReceiptScanSheet { reading, attachmentID in
                    // Fills the form in. Nothing is recorded until the owner
                    // taps Save on this screen, exactly as if they had typed
                    // it — a scan is a shortcut, not a second way to commit.
                    if let date = reading.date { draft.performedOn = date }
                    if let total = reading.total {
                        draft.totalCostText = NSDecimalNumber(decimal: total).stringValue
                    }
                    if let merchant = reading.merchant {
                        draft.performer = .shop(name: merchant)
                        isShop = true
                    }
                    if let attachmentID { draft.attachmentIDs.append(attachmentID) }
                }
            }
            .sheet(isPresented: $showingExtraTasks) {
                ExtraTaskPicker(vehicle: vehicle, selected: $draft.extraDefinitionIDs)
            }
            .onChange(of: photoItem) { _, newValue in
                guard let newValue else { return }
                Task { await attach(newValue) }
            }
            .onAppear(perform: prepare)
        }
    }

    private func prepare() {
        guard !didPrepare else { return }
        didPrepare = true

        if let editingRecord {
            draft.selectedPlanItemIDs = Set(editingRecord.items.compactMap(\.planItemID))
            let plannedDefinitions = Set(
                model.snapshot.planItems(for: vehicle.id).map(\.definitionID)
            )
            draft.extraDefinitionIDs = Set(
                editingRecord.items
                    .filter { $0.planItemID == nil || !plannedDefinitions.contains($0.definitionID) }
                    .map(\.definitionID)
            )
            draft.attachmentIDs = editingRecord.attachmentIDs
            draft.notes = editingRecord.notes ?? ""
            if let cost = editingRecord.totalCost {
                draft.totalCostText = DecimalText.plain(cost.amount)
            }
            if let name = editingRecord.performer.shopName {
                isShop = true
                shopName = name
            }
        } else if let preselectedPlanItemID {
            draft.selectedPlanItemIDs = [preselectedPlanItemID]
        }

        if draft.odometerAmount == nil, let latest = model.latestReading(for: vehicle.id) {
            draft.odometerAmount = latest.value.amount
        }
        if let amount = draft.odometerAmount {
            odometerText = String(amount)
        }
    }

    private func toggle(_ id: UUID) {
        if draft.selectedPlanItemIDs.contains(id) {
            draft.selectedPlanItemIDs.remove(id)
        } else {
            draft.selectedPlanItemIDs.insert(id)
        }
    }

    private func attach(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            model.alert = AppAlert(
                title: "Could not read that photo",
                message: "Odomind could not load the image you picked.",
                recoverySuggestion: "Try a different photo, or take a new one."
            )
            return
        }
        if let id = model.addAttachment(data: data, contentType: "image/jpeg") {
            draft.attachmentIDs.append(id)
        }
    }

    private func save() {
        draft.performer = isShop ? .shop(name: shopName) : .doItYourself
        if model.saveService(draft) != nil {
            dismiss()
        }
    }
}

/// Lets the owner record a job that is not in their plan, without adding it to
/// the schedule.
struct ExtraTaskPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let vehicle: Vehicle
    @Binding var selected: Set<String>
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered, id: \.definition.id) { suggestion in
                    Button {
                        if selected.contains(suggestion.definition.id) {
                            selected.remove(suggestion.definition.id)
                        } else {
                            selected.insert(suggestion.definition.id)
                        }
                    } label: {
                        HStack {
                            Image(systemName: selected.contains(suggestion.definition.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected.contains(suggestion.definition.id) ? Color.accentColor : Color.secondary)
                            Text(suggestion.definition.title).foregroundStyle(.primary)
                            Spacer()
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search the catalog")
            .navigationTitle("Other work")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var filtered: [SuggestedTask] {
        model.allSuggestions(for: vehicle)
            .filter { $0.definition.matches(query: searchText) }
            .sorted { $0.definition.title < $1.definition.title }
    }
}
