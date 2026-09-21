import SwiftUI
import OdomindCore

/// Adding a vehicle, step by step.
///
/// Each step is answerable in a few seconds, and every step after identity can
/// be skipped. "I don't know" is a first-class answer throughout: it is recorded
/// as not knowing, never as "just serviced".
struct AddVehicleFlow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var draft = VehicleDraft()
    @State private var step: Step = .identity
    @State private var didPrepare = false

    /// Three steps, and the last two are skippable.
    ///
    /// Build 1 had four, and the third asked an ordinary driver whether their
    /// engine used a timing belt or a timing chain. Configuration questions
    /// now appear only where a job actually depends on the answer.
    enum Step: Int, CaseIterable {
        case find
        case confirm
        case plan

        var title: String {
            switch self {
            case .find: return "Find your vehicle"
            case .confirm: return "Confirm and start"
            case .plan: return "Your starter plan"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .find:
                    FindVehicleStep(draft: $draft)
                case .confirm:
                    ConfirmStep(draft: $draft)
                case .plan:
                    TaskSelectionStep(draft: $draft)
                }
            }
            .navigationTitle(step.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if step == .plan {
                        Button("Add vehicle") { finish() }
                            .disabled(!draft.isReadyToSave)
                            .accessibilityIdentifier("addVehicle.finish")
                    } else {
                        Button("Next") { advance() }
                            .disabled(step == .find && !draft.isReadyToSave)
                            .accessibilityIdentifier("addVehicle.next")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    if step != .find {
                        Button("Back") { retreat() }
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        StepIndicator(current: step)
                        Spacer()
                        if step == .confirm {
                            Button("Skip") { advance() }
                                .font(.callout)
                        }
                    }
                }
            }
            .onAppear(perform: prepare)
        }
    }

    private func prepare() {
        guard !didPrepare else { return }
        didPrepare = true
        draft.displayUnit = Locale.current.measurementSystem == .metric ? .kilometers : .miles
        draft.odometerDate = model.clock.now
    }

    private func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    private func retreat() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    private func finish() {
        if model.addVehicle(from: draft) != nil {
            dismiss()
        }
    }
}

private struct StepIndicator: View {
    let current: AddVehicleFlow.Step

    var body: some View {
        HStack(spacing: Theme.Spacing.tight) {
            ForEach(AddVehicleFlow.Step.allCases, id: \.rawValue) { step in
                Circle()
                    .fill(step.rawValue <= current.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(
            Text("Step \(current.rawValue + 1) of \(AddVehicleFlow.Step.allCases.count): \(current.title)")
        )
    }
}

// MARK: - Step 1: find the vehicle

/// Search first, typing second, VIN third.
///
/// Build 1 put three free-text boxes here and left the provider's model search
/// unused. Now a query like "2010 Jeep Wrangler" produces real selectable
/// models from the lookup service, and what the owner picks is recorded as
/// having come from there. Typing it by hand still works, still works offline,
/// and is recorded as entered by the owner rather than dressed up as a match.
private struct FindVehicleStep: View {
    @Environment(AppModel.self) private var model
    @Binding var draft: VehicleDraft

    @State private var query = ""
    @State private var search: VehicleSearchModel?
    @State private var showingManualEntry = false
    @State private var showingVINEntry = false

    var body: some View {
        Form {
            Section {
                TextField("Try “2010 Jeep Wrangler”", text: $query)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
                    .accessibilityIdentifier("addVehicle.search")
                    .onChange(of: query) { _, newValue in
                        search?.search(newValue)
                    }
            } header: {
                Text("Search")
            } footer: {
                // One quiet line, once — not a consent modal per keystroke.
                // The VIN path keeps its own explicit disclosure, because a
                // VIN identifies a specific vehicle and a model name does not.
                Text("Searching sends the year and make to \(model.identificationProvider.displayName) (\(model.identificationProvider.contactedHost)) to list its models. Nothing about you is sent.")
            }

            if let search { resultsSection(search) }

            if draft.isReadyToSave {
                Section {
                    ValueRow(label: "Selected", value: draft.identity.displayName)
                    TextField("Nickname (optional)", text: $draft.nickname)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("addVehicle.nickname")
                } header: {
                    Text("Your vehicle")
                } footer: {
                    Text("A nickname like \"the Jeep\" is shown instead of the year, make and model.")
                }
            }

            Section {
                Button {
                    showingManualEntry = true
                } label: {
                    Label("Type it in myself", systemImage: "keyboard")
                }
                .accessibilityIdentifier("addVehicle.manual")

                Button {
                    showingVINEntry = true
                } label: {
                    Label("Use my VIN", systemImage: "barcode.viewfinder")
                }
                .accessibilityIdentifier("addVehicle.useVIN")
            } header: {
                Text("Other ways")
            } footer: {
                Text("Typing it in always works, including with no connection. A VIN can also fill in the engine and drivetrain, and Odomind asks before sending it.")
            }

            if let decode = draft.decodeResult {
                Section {
                    ForEach(decode.reportedFields) { field in
                        ValueRow(label: field.name, value: field.value)
                    }
                } header: {
                    Text("What the lookup returned")
                } footer: {
                    Text("This is what \(model.identificationProvider.displayName) reported. It identifies the vehicle; it does not tell Odomind what fluids or intervals it takes.")
                }
            }
        }
        .sheet(isPresented: $showingManualEntry) {
            ManualIdentityEntry(draft: $draft)
        }
        .sheet(isPresented: $showingVINEntry) {
            VINEntryView { result in apply(result) }
        }
        .onAppear {
            if search == nil {
                search = VehicleSearchModel(provider: model.identificationProvider, clock: model.clock)
            }
        }
        .onDisappear { search?.cancel() }
    }

    @ViewBuilder
    private func resultsSection(_ search: VehicleSearchModel) -> some View {
        switch search.state {
        case .idle:
            EmptyView()
        case .needsMoreDetail(let hint):
            Section { QuietNote(text: hint, symbolName: "text.magnifyingglass") }
        case .searching:
            Section {
                HStack {
                    ProgressView()
                    Text("Looking…").foregroundStyle(Theme.Palette.secondaryText)
                }
            }
        case .empty(let message):
            Section {
                QuietNote(text: message)
                Button("Type it in myself") { showingManualEntry = true }
            }
        case .offline(let message):
            Section {
                // A provider failure never blocks adding a vehicle.
                QuietNote(text: message, symbolName: "wifi.slash")
                Button("Type it in myself") { showingManualEntry = true }
                    .accessibilityIdentifier("addVehicle.manualFromError")
            }
        case .results(let results):
            Section {
                ForEach(results) { result in
                    Button {
                        select(result)
                    } label: {
                        HStack {
                            Text(result.displayName)
                                .foregroundStyle(Theme.Palette.primaryText)
                            Spacer()
                            if draft.identity.model == result.model,
                               draft.identity.modelYear == result.modelYear {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.Palette.accent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("addVehicle.result")
                }
            } header: {
                Text("Matches")
            }
        }
    }

    private func select(_ result: VehicleSearchResult) {
        var identity = result.identity
        // Anything the owner had already supplied that the search does not
        // carry — a trim they typed — is kept.
        identity.trim = draft.identity.trim
        identity.vin = draft.identity.vin
        draft.identity = identity
    }

    private func apply(_ result: VehicleDecodeResult) {
        draft.decodeResult = result
        draft.identity = result.identity
        draft.configuration = result.configuration
    }
}

/// The always-available path. Explicitly labelled as the owner's own entry, so
/// it is never recorded as a database match.
private struct ManualIdentityEntry: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var draft: VehicleDraft

    @State private var yearText = ""
    @State private var make = ""
    @State private var vehicleModel = ""
    @State private var trim = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Year", text: $yearText)
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("addVehicle.year")
                    TextField("Make", text: $make)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("addVehicle.make")
                    TextField("Model", text: $vehicleModel)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("addVehicle.model")
                    TextField("Trim (optional)", text: $trim)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Odomind records this as entered by you. It will not describe it as a database match, because it is not one.")
                }
            }
            .navigationTitle("Type it in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save() }
                        .disabled(make.trimmingCharacters(in: .whitespaces).isEmpty
                            || vehicleModel.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("addVehicle.manualDone")
                }
            }
            .onAppear {
                if let year = draft.identity.modelYear { yearText = String(year) }
                make = draft.identity.make
                vehicleModel = draft.identity.model
                trim = draft.identity.trim ?? ""
            }
        }
    }

    private func save() {
        draft.identity = VehicleIdentity(
            modelYear: Int(yearText.filter(\.isNumber)),
            make: make.trimmingCharacters(in: .whitespacesAndNewlines),
            model: vehicleModel.trimmingCharacters(in: .whitespacesAndNewlines),
            trim: trim.isEmpty ? nil : trim,
            vin: draft.identity.vin,
            identityProvenance: .userEntered
        )
        dismiss()
    }
}

// MARK: - Step 2: confirm and start

/// One screen: what Odomind matched, the mileage, and nothing else.
///
/// The configuration questions here are only the ones that change which jobs
/// *exist* — an electric car has no engine oil, a two-wheel-drive car has no
/// transfer case — and only when the answer is not already known. Camshaft
/// drive, market and usage profile are not asked during setup at all; they are
/// asked later, on the job that needs them, where the question makes sense.
private struct ConfirmStep: View {
    @Environment(AppModel.self) private var model
    @Binding var draft: VehicleDraft

    @State private var odometerText = ""
    @State private var didPrepare = false

    var body: some View {
        Form {
            Section {
                ValueRow(label: "Vehicle", value: draft.identity.displayName)
                if draft.identity.identityProvenance == .userEntered {
                    QuietNote(text: "Entered by you, not matched against a database.", symbolName: "person.crop.circle")
                }
                VehicleSilhouettePreview(draft: draft)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            } header: {
                Text("What Odomind will track")
            }

            Section {
                HStack {
                    TextField("Current reading", text: $odometerText)
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("addVehicle.odometer")
                        .onChange(of: odometerText) { _, newValue in
                            draft.odometerAmount = Int(newValue.filter(\.isNumber))
                        }
                    Text(draft.displayUnit.abbreviation).foregroundStyle(.secondary)
                }
                Picker("Units", selection: $draft.displayUnit) {
                    Text("Miles").tag(DistanceUnit.miles)
                    Text("Kilometers").tag(DistanceUnit.kilometers)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Mileage")
            } footer: {
                Text("Read it off the dashboard. You can skip this — mileage-based due points simply wait until you add one.")
            }

            if !openQuestions.isEmpty {
                Section {
                    if openQuestions.contains(.powertrain) {
                        Picker("Runs on", selection: $draft.configuration.powertrain) {
                            ForEach(PowertrainKind.allCases, id: \.self) { value in
                                Text(value.displayName).tag(value)
                            }
                        }
                        .accessibilityIdentifier("confirm.powertrain")
                    }
                    if openQuestions.contains(.drivetrain) {
                        Picker("Driven wheels", selection: $draft.configuration.drivetrain) {
                            ForEach(DrivetrainLayout.allCases, id: \.self) { value in
                                Text(value.displayName).tag(value)
                            }
                        }
                        .accessibilityIdentifier("confirm.drivetrain")
                    }
                } header: {
                    Text("A couple of details")
                } footer: {
                    Text("These decide which jobs apply at all — an electric vehicle never gets an oil change. Leave either unset and Odomind keeps the jobs that depend on it out of your plan rather than guessing.")
                }
            }

            if let decode = draft.decodeResult, !decode.providerMessages.isEmpty {
                Section {
                    ForEach(Array(decode.providerMessages.enumerated()), id: \.offset) { _, message in
                        InlineNotice(kind: .caution, message: message)
                    }
                } header: {
                    Text("From the lookup service")
                }
            }
        }
        .onAppear(perform: prepare)
    }

    /// Only the two questions that gate whole categories of work. Anything the
    /// VIN decode already answered is not asked again.
    private var openQuestions: Set<ConfigurationQuestion> {
        var questions: Set<ConfigurationQuestion> = []
        if draft.configuration.powertrain == .unknown { questions.insert(.powertrain) }
        if draft.configuration.drivetrain == .unknown { questions.insert(.drivetrain) }
        return questions
    }

    private func prepare() {
        guard !didPrepare else { return }
        didPrepare = true
        if let amount = draft.odometerAmount { odometerText = String(amount) }
    }
}

/// The vehicle as Odomind will draw it, shown before the owner commits.
private struct VehicleSilhouettePreview: View {
    let draft: VehicleDraft

    var body: some View {
        let vehicle = Vehicle(
            nickname: draft.nickname.isEmpty ? nil : draft.nickname,
            identity: draft.identity,
            configuration: draft.configuration
        )
        let resolution = VehicleArtworkResolver.resolve(vehicle: vehicle, hasPhoto: false)

        VStack(spacing: Theme.Spacing.small) {
            VehicleArtworkView(
                resolution: resolution,
                paint: .default,
                accessibilityText: "\(vehicle.identity.displayName). \(resolution.disclosure)"
            )
            .frame(height: 110)
            .frame(maxWidth: .infinity)
            .background(Theme.Palette.artworkGround)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))

            if !resolution.isExactMatch {
                Text("You can change the picture and its colour later.")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)
            }
        }
        .padding(.vertical, Theme.Spacing.small)
    }
}
