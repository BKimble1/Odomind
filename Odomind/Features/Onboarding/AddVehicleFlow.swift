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
    @State private var step: Step = .find
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
                        .accessibilityIdentifier("addVehicle.cancel")
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
                TextField("Search make or model", text: $query)
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
                Text("Searching sends the make to \(model.identificationProvider.displayName) (\(model.identificationProvider.contactedHost)) to list its models, and the year too if you typed one. Nothing about you is sent.")
            }

            if let search { resultsSection(search) }

            if draft.isReadyToSave {
                Section {
                    ModelYearStrip(
                        years: modelYears,
                        selected: draft.identity.modelYear
                    ) { year in
                        draft.identity.modelYear = year
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } header: {
                    Text("Which year?")
                } footer: {
                    Text(yearFooter)
                }
            }

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
        .task {
            if search == nil {
                search = VehicleSearchModel(provider: model.identificationProvider, clock: model.clock)
            }
            // Off the main actor, and never blocking the field: searching
            // works before this lands, against the provider alone.
            await search?.loadIndex()
        }
        .onDisappear { search?.cancel() }
    }

    /// The years to offer, newest first.
    ///
    /// Next year is in the list because a model year ships ahead of the
    /// calendar year it is named for, and 1981 is the floor because that is
    /// where the seventeen-character VIN — and every year-keyed lookup
    /// Odomind can make — begins. Anything older is still addable by typing
    /// it in; it simply has no published configuration list to offer.
    private var modelYears: [Int] {
        let current = Calendar(identifier: .gregorian).component(.year, from: model.clock.now)
        return Array(stride(from: current + 1, through: 1981, by: -1))
    }

    private var yearFooter: String {
        guard draft.identity.modelYear == nil else {
            return "Tap another year if that is not the one."
        }
        return "A year is what lets Odomind look up which engines this was sold with, "
            + "instead of asking you to remember. You can skip it — the questions it "
            + "would have answered get asked on the next screen instead."
    }

    @ViewBuilder
    private func resultsSection(_ search: VehicleSearchModel) -> some View {
        switch search.state {
        case .idle:
            EmptyView()
        case .makeSuggestions(let makes):
            Section {
                ForEach(makes, id: \.self) { make in
                    Button {
                        query = make.capitalized
                        search.search(query)
                    } label: {
                        HStack {
                            Text(make.capitalized).foregroundStyle(Theme.Palette.primaryText)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(Theme.Palette.secondaryText)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("addVehicle.makeSuggestion")
                }
            } header: {
                Text("Makes")
            }
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
                               result.modelYear == nil || draft.identity.modelYear == result.modelYear {
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

    /// Replaces the whole identity, and drops everything that described the
    /// vehicle that is no longer selected.
    ///
    /// Build 2 carried the previous VIN and trim across, and left
    /// `configuration` — engine, drivetrain, transmission from an earlier VIN
    /// decode — entirely untouched. Choose a Wrangler by VIN, change your mind
    /// and pick a Camry, and the Camry inherited the Jeep's VIN and its 3.8
    /// litre four-wheel drive. A trim belongs to the model it was typed for;
    /// so does a VIN; so does everything a decode produced.
    private func select(_ result: VehicleSearchResult) {
        let sameVehicle = draft.identity.make.caseInsensitiveCompare(result.make) == .orderedSame
            && draft.identity.model.caseInsensitiveCompare(result.model) == .orderedSame

        guard !sameVehicle else {
            // Re-tapping the same row should not discard what the owner has
            // already confirmed about it.
            draft.identity.modelYear = result.modelYear ?? draft.identity.modelYear
            return
        }

        draft.identity = result.identity
        draft.configuration = VehicleConfiguration()
        draft.decodeResult = nil
        // A trim word the search carried is a hint about *this* model, and is
        // applied by the confirm step rather than inherited from the last one.
        draft.identity.trim = nil
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
    /// The configuration as it stood before any option was applied.
    ///
    /// Options are applied to *this*, never to the result of the previous
    /// one. Otherwise picking the four-wheel-drive variant and then the
    /// two-wheel-drive one leaves whatever the first stated and the second
    /// did not — one car's facts wearing another's label.
    @State private var configurationBeforeOptions: VehicleConfiguration?
    /// Set when the owner says none of the listed configurations is theirs.
    @State private var isAnsweringManually = false

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

            configurationSection

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
        // Keyed on the vehicle, so backing up and choosing a different one
        // asks again rather than offering the previous car's engines.
        .task(id: VehicleOptionsService.key(
            modelYear: draft.identity.modelYear,
            make: draft.identity.make,
            model: draft.identity.model
        )) {
            // A different vehicle is a different set of answers, so the two
            // decisions made about the previous one are dropped with it.
            configurationBeforeOptions = nil
            isAnsweringManually = false
            model.vehicleOptions.resolve(
                modelYear: draft.identity.modelYear,
                make: draft.identity.make,
                model: draft.identity.model
            )
        }
    }

    /// Only the two questions that gate whole categories of work. Anything the
    /// VIN decode already answered is not asked again.
    private var openQuestions: Set<ConfigurationQuestion> {
        var questions: Set<ConfigurationQuestion> = []
        if draft.configuration.powertrain == .unknown { questions.insert(.powertrain) }
        if draft.configuration.drivetrain == .unknown { questions.insert(.drivetrain) }
        return questions
    }

    /// Which engine and drivetrain, asked with the answers a provider
    /// published rather than with the whole enum.
    ///
    /// Build 2 offered every powertrain ever built for every car, and every
    /// drivetrain layout, and asked the owner to remember. The options here
    /// are the configurations the vehicle was sold in. The generic pickers
    /// are still underneath, for the vehicles no list covers — which is an
    /// honest fallback and not the normal experience.
    @ViewBuilder
    private var configurationSection: some View {
        switch model.vehicleOptions.status {
        case .looking:
            Section {
                HStack(spacing: Theme.Spacing.small) {
                    ProgressView().controlSize(.small)
                    Text("Checking which engines this was sold with…")
                        .foregroundStyle(Theme.Palette.secondaryText)
                }
            }

        case .options(let options) where !isAnsweringManually:
            Section {
                ForEach(options) { option in
                    ConfigurationOptionRow(
                        option: option,
                        isSelected: model.vehicleOptions.selectedOptionID == option.id
                    ) {
                        select(option)
                    }
                }
                // Every list of configurations is a list of what was sold in
                // one market. Somebody with an import, a conversion or a
                // vehicle the list simply misses needs a way through that is
                // not picking the closest wrong answer.
                Button("None of these is mine") {
                    isAnsweringManually = true
                    model.vehicleOptions.selectedOptionID = nil
                    if let base = configurationBeforeOptions { draft.configuration = base }
                }
                .accessibilityIdentifier("confirm.noneOfThese")
            } header: {
                Text("Which one is yours?")
            } footer: {
                VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                    Text("These are the configurations this year, make and model was sold in. Picking one fills in the engine and drivetrain, which is what decides whether a job like a transfer case service applies at all.")
                    if let first = options.first {
                        Text(first.sourceLine)
                            .foregroundStyle(Theme.Palette.secondaryText)
                    }
                    Text("Odomind sent only the year, make and model. Not your VIN, and not your mileage.")
                        .foregroundStyle(Theme.Palette.secondaryText)
                }
            }

        case .idle, .none, .options:
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
                    VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                        if case .none(let reason) = model.vehicleOptions.status {
                            Text(reason).foregroundStyle(Theme.Palette.secondaryText)
                        }
                        Text("These decide which jobs apply at all — an electric vehicle never gets an oil change. Leave either unset and Odomind keeps the jobs that depend on it out of your plan rather than guessing.")
                    }
                }
            }
        }
    }

    private func select(_ option: VehicleConfigurationOption) {
        let base = configurationBeforeOptions ?? draft.configuration
        configurationBeforeOptions = base
        model.vehicleOptions.selectedOptionID = option.id
        draft.configuration = option.applied(to: base)
    }

    private func prepare() {
        guard !didPrepare else { return }
        didPrepare = true
        if let amount = draft.odometerAmount { odometerText = String(amount) }
    }
}

/// The model year, asked after the vehicle instead of before it.
///
/// Build 3 removed the year from the *precondition* for searching, which is
/// what made "wrangler" on its own work at all. It then never asked for it
/// anywhere else, so a vehicle found that way reached the confirm step with no
/// year — and the configuration lookup, which is keyed on year, make and
/// model, could only report that it needed one. The screen said so and offered
/// nowhere to say it. Found by looking at the screenshot, not by a test: every
/// identifier was present and every element existed.
private struct ModelYearStrip: View {
    let years: [Int]
    let selected: Int?
    let onSelect: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.small) {
                    ForEach(years, id: \.self) { year in
                        Button {
                            onSelect(year)
                        } label: {
                            Text(String(year))
                                .font(.callout.weight(year == selected ? .semibold : .regular))
                                .monospacedDigit()
                                .padding(.horizontal, Theme.Spacing.medium)
                                .padding(.vertical, Theme.Spacing.small)
                                .frame(minWidth: 44, minHeight: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                                        .fill(year == selected ? Theme.Palette.accent : Theme.Palette.raised)
                                )
                                .foregroundStyle(year == selected ? Theme.Palette.onAccent : Theme.Palette.primaryText)
                        }
                        .buttonStyle(.plain)
                        .id(year)
                        .accessibilityIdentifier("addVehicle.modelYear.\(year)")
                        .accessibilityAddTraits(year == selected ? [.isButton, .isSelected] : .isButton)
                    }
                }
                .padding(.horizontal, Theme.Spacing.large)
                .padding(.vertical, Theme.Spacing.small)
            }
            .onAppear {
                // A year already known — from a VIN decode, or from a query
                // that carried one — starts in view rather than forty taps
                // along a strip that opens on next year.
                guard let selected else { return }
                proxy.scrollTo(selected, anchor: .center)
            }
        }
    }
}

/// One configuration the vehicle was sold in, in the provider's own words.
private struct ConfigurationOptionRow: View {
    let option: VehicleConfigurationOption
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.medium) {
                VStack(alignment: .leading, spacing: 2) {
                    // Verbatim. Paraphrasing would put Odomind's reading in
                    // front of what the source actually says.
                    Text(option.label)
                        .foregroundStyle(Theme.Palette.primaryText)
                        .multilineTextAlignment(.leading)
                    if let implied = impliedSummary {
                        Text(implied)
                            .font(.caption)
                            .foregroundStyle(Theme.Palette.secondaryText)
                    }
                }
                Spacer(minLength: Theme.Spacing.small)
                if isSelected {
                    // The word, not only the colour.
                    Label("Selected", systemImage: "checkmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(Theme.Palette.accent)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("confirm.option.\(option.id)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// What picking this would set, so the consequence is visible before the
    /// tap rather than discovered afterwards.
    private var impliedSummary: String? {
        var parts: [String] = []
        if option.powertrain != .unknown { parts.append(option.powertrain.displayName) }
        if option.drivetrain != .unknown { parts.append(option.drivetrain.displayName) }
        if option.transmission != .unknown { parts.append(option.transmission.displayName) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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
