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

    enum Step: Int, CaseIterable {
        case identity
        case confirm
        case mileage
        case tasks

        var title: String {
            switch self {
            case .identity: return "Your vehicle"
            case .confirm: return "Confirm"
            case .mileage: return "Mileage"
            case .tasks: return "What to track"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .identity:
                    IdentityStep(draft: $draft)
                case .confirm:
                    ConfirmStep(draft: $draft)
                case .mileage:
                    MileageStep(draft: $draft)
                case .tasks:
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
                    if step == .tasks {
                        Button("Add vehicle") { finish() }
                            .disabled(!draft.isReadyToSave)
                            .accessibilityIdentifier("addVehicle.finish")
                    } else {
                        Button("Next") { advance() }
                            .disabled(step == .identity && !draft.isReadyToSave)
                            .accessibilityIdentifier("addVehicle.next")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    if step != .identity {
                        Button("Back") { retreat() }
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        StepIndicator(current: step)
                        Spacer()
                        if step != .identity, step != .tasks {
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

// MARK: - Step 1: identity

private struct IdentityStep: View {
    @Environment(AppModel.self) private var model
    @Binding var draft: VehicleDraft

    @State private var yearText = ""
    @State private var showingVINEntry = false

    var body: some View {
        Form {
            Section {
                TextField("Nickname (optional)", text: $draft.nickname)
                    .autocorrectionDisabled()
            } footer: {
                Text("Something like \"the Jeep\". Shown instead of the year, make and model.")
            }

            Section {
                TextField("Year", text: $yearText)
                    .keyboardType(.numberPad)
                    .accessibilityIdentifier("addVehicle.year")
                    .onChange(of: yearText) { _, newValue in
                        draft.identity.modelYear = Int(newValue.filter(\.isNumber))
                    }
                TextField("Make", text: $draft.identity.make)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("addVehicle.make")
                TextField("Model", text: $draft.identity.model)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("addVehicle.model")
                TextField("Trim (optional)", text: Binding(
                    get: { draft.identity.trim ?? "" },
                    set: { draft.identity.trim = $0.isEmpty ? nil : $0 }
                ))
                .autocorrectionDisabled()
            } header: {
                Text("Vehicle")
            } footer: {
                Text("Typing it in always works, and works offline.")
            }

            Section {
                Button {
                    showingVINEntry = true
                } label: {
                    Label("Use my VIN instead", systemImage: "barcode.viewfinder")
                }
            } footer: {
                Text("Odomind can look up the year, make, model and engine from your VIN. It asks before sending anything.")
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
        .sheet(isPresented: $showingVINEntry) {
            VINEntryView { result in
                apply(result)
            }
        }
        .onAppear {
            if yearText.isEmpty, let year = draft.identity.modelYear {
                yearText = String(year)
            }
        }
    }

    private func apply(_ result: VehicleDecodeResult) {
        draft.decodeResult = result
        draft.identity = result.identity
        draft.configuration = result.configuration
        if let year = result.identity.modelYear { yearText = String(year) }
    }
}

// MARK: - Step 2: confirm configuration

private struct ConfirmStep: View {
    @Binding var draft: VehicleDraft

    var body: some View {
        Form {
            if let decode = draft.decodeResult, !decode.providerMessages.isEmpty {
                Section {
                    ForEach(Array(decode.providerMessages.enumerated()), id: \.offset) { _, message in
                        InlineNotice(kind: .caution, message: message)
                    }
                } header: {
                    Text("From the lookup service")
                }
            }

            if let decode = draft.decodeResult, !decode.missingFields.isEmpty {
                Section {
                    Text(decode.missingFields.joined(separator: ", "))
                        .font(.callout)
                } header: {
                    Text("The lookup did not have")
                } footer: {
                    Text("Fill in anything you know. Anything left unset simply keeps the tasks that depend on it out of your plan.")
                }
            }

            Section {
                Picker("Runs on", selection: $draft.configuration.powertrain) {
                    ForEach(PowertrainKind.allCases, id: \.self) { value in
                        Text(value.displayName).tag(value)
                    }
                }
                Picker("Transmission", selection: $draft.configuration.transmission) {
                    ForEach(TransmissionKind.allCases, id: \.self) { value in
                        Text(value.displayName).tag(value)
                    }
                }
                Picker("Drivetrain", selection: $draft.configuration.drivetrain) {
                    ForEach(DrivetrainLayout.allCases, id: \.self) { value in
                        Text(value.displayName).tag(value)
                    }
                }
            } header: {
                Text("Configuration")
            } footer: {
                Text("These decide which tasks Odomind offers. An electric vehicle gets no engine-oil task; a two-wheel-drive vehicle gets no transfer case.")
            }

            if draft.configuration.powertrain.hasCombustionEngine {
                Section {
                    Picker("Camshaft drive", selection: $draft.configuration.camshaftDrive) {
                        ForEach(CamshaftDrive.allCases, id: \.self) { value in
                            Text(value.displayName).tag(value)
                        }
                    }
                } footer: {
                    Text(ConfigurationQuestion.camshaftDrive.rationale)
                }
            }

            Section {
                Picker("Market", selection: $draft.configuration.market) {
                    ForEach(Market.allCases, id: \.self) { value in
                        Text(value.displayName).tag(value)
                    }
                }
            }
        }
    }
}

// MARK: - Step 3: mileage

private struct MileageStep: View {
    @Environment(AppModel.self) private var model
    @Binding var draft: VehicleDraft

    @State private var odometerText = ""
    @State private var knowsTypicalDistance = false
    @State private var typicalText = ""

    var body: some View {
        Form {
            Section {
                Picker("Units", selection: $draft.displayUnit) {
                    Text("Miles").tag(DistanceUnit.miles)
                    Text("Kilometers").tag(DistanceUnit.kilometers)
                }
                .pickerStyle(.segmented)
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
                DatePicker("As of", selection: $draft.odometerDate, in: ...Date(), displayedComponents: .date)
            } header: {
                Text("Odometer")
            } footer: {
                Text("Read it off your dashboard. You can skip this and add it later, but next-due mileage will not work until you do.")
            }

            Section {
                DatePicker(
                    "Entered service",
                    selection: Binding(
                        get: { draft.inServiceOn ?? defaultInServiceDate },
                        set: { draft.inServiceOn = $0 }
                    ),
                    in: ...Date(),
                    displayedComponents: .date
                )
            } header: {
                Text("Age")
            } footer: {
                Text("Roughly when the vehicle first went on the road. Only used for age-based manufacturer milestones; skip it if you are not sure.")
            }

            Section {
                Toggle("I know roughly how far I drive", isOn: $knowsTypicalDistance)
                if knowsTypicalDistance {
                    HStack {
                        TextField("Per month", text: $typicalText)
                            .keyboardType(.numberPad)
                            .onChange(of: typicalText) { _, newValue in
                                let amount = Int(newValue.filter(\.isNumber))
                                draft.declaredTypicalDistancePerMonth = amount.map { Distance($0, draft.displayUnit) }
                            }
                        Text("\(draft.displayUnit.abbreviation)/month").foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("Optional. It lets Odomind estimate dates before it has enough readings of its own. Estimates are always labelled as estimates.")
            }
        }
    }

    private var defaultInServiceDate: Date {
        guard let year = draft.identity.modelYear else { return model.clock.now }
        var components = DateComponents()
        components.year = year
        components.month = 1
        components.day = 1
        return model.calendar.date(from: components) ?? model.clock.now
    }
}
