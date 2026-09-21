import SwiftUI
import OdomindCore

/// Home: which vehicle, what is coming, and the two things an owner actually
/// does — record mileage and record work.
///
/// The hierarchy is deliberate and is a direct answer to Build 1's Today
/// screen. The vehicle header is one row rather than a card that repeated the
/// vehicle's name under its own title. Search comes next because "what is this
/// job" and "what part do I need" are the questions people arrive with. Then a
/// short agenda of things that can actually be acted on. Then logging.
///
/// What is gone: the green all-clear shown while fifteen tasks had no history,
/// and the fifteen setup alerts underneath it.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationRouter.self) private var router

    @State private var showingMileageEntry = false
    @State private var showingServiceLog = false
    @State private var quickLog: QuickLogRequest?
    @State private var searchText = ""
    @State private var searchScope: SearchScope = .jobs

    enum SearchScope: String, CaseIterable, Hashable {
        case jobs
        case parts

        var title: String {
            switch self {
            case .jobs: return "Jobs"
            case .parts: return "Parts"
            }
        }
    }

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.homePath) {
            Group {
                if let vehicle = model.selectedVehicle {
                    content(for: vehicle)
                } else {
                    NoVehicleView()
                }
            }
            .navigationTitle("Home")
            .background(Theme.Palette.page)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { VehiclePickerBar() }
            }
            .odomindDestinations()
            .sheet(isPresented: $showingMileageEntry) {
                if let vehicle = model.selectedVehicle { MileageEntrySheet(vehicle: vehicle) }
            }
            .sheet(isPresented: $showingServiceLog) {
                if let vehicle = model.selectedVehicle { LogServiceView(vehicle: vehicle) }
            }
            .sheet(item: $quickLog) { request in
                QuickLogSheet(request: request)
            }
            .onChange(of: router.presentMileageEntry) { _, newValue in
                if newValue {
                    showingMileageEntry = true
                    router.presentMileageEntry = false
                }
            }
            .onChange(of: router.presentServiceLog) { _, newValue in
                if newValue {
                    showingServiceLog = true
                    router.presentServiceLog = false
                }
            }
        }
    }

    @ViewBuilder
    private func content(for vehicle: Vehicle) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.large) {
                Card(padding: Theme.Spacing.medium) {
                    VehicleHeaderRow(vehicle: vehicle) { showingMileageEntry = true }
                }

                searchSection(for: vehicle)

                if searchText.isEmpty {
                    upNextSection(for: vehicle)
                    actionsSection(for: vehicle)
                    recentSection(for: vehicle)
                }

                if vehicle.isDemo, let disclaimer = model.demoDisclaimer {
                    QuietNote(text: disclaimer, symbolName: "exclamationmark.triangle")
                        .padding(.horizontal, Theme.Spacing.tight)
                }
            }
            .padding(Theme.Spacing.large)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable {
            model.refresh()
            await model.syncReminders()
        }
    }

    // MARK: - Search

    @ViewBuilder
    private func searchSection(for vehicle: Vehicle) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            HStack(spacing: Theme.Spacing.small) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .accessibilityHidden(true)
                TextField("Search jobs and parts", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("home.search")
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.Palette.secondaryText)
                    }
                    .accessibilityLabel(Text("Clear search"))
                }
            }
            .padding(.horizontal, Theme.Spacing.medium)
            .padding(.vertical, Theme.Spacing.medium)
            .background(Theme.Palette.raised, in: RoundedRectangle(cornerRadius: Theme.Radius.tile))

            if !searchText.isEmpty {
                // The query survives the switch, which is the whole point of
                // having the segments here rather than two separate screens.
                Picker("What to search", selection: $searchScope) {
                    ForEach(SearchScope.allCases, id: \.self) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("home.searchScope")

                switch searchScope {
                case .jobs: jobResults(for: vehicle)
                case .parts: partResults(for: vehicle)
                }
            }
        }
    }

    @ViewBuilder
    private func jobResults(for vehicle: Vehicle) -> some View {
        let results = model.searchJobs(query: searchText, vehicle: vehicle)
        if results.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                    Text("Nothing matching “\(searchText)”")
                        .font(.subheadline.weight(.medium))
                    Text("Try a simpler word — “oil”, “tires”, “brakes” — or add it as your own job.")
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.secondaryText)
                    Button("Create a custom job") { router.homePath.append(JobRoute.customTask) }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.Palette.accent)
                }
            }
        } else {
            VStack(spacing: 0) {
                ForEach(Array(results.prefix(8))) { result in
                    JobSearchRow(result: result) {
                        if let planItemID = result.planItemID {
                            router.homePath.append(JobRoute.task(planItemID))
                        } else {
                            router.homePath.append(JobRoute.addTask)
                        }
                    }
                    if result.id != results.prefix(8).last?.id {
                        Divider().overlay(Theme.Palette.separator)
                    }
                }
            }
            .background(Theme.Palette.raised, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        }
    }

    @ViewBuilder
    private func partResults(for vehicle: Vehicle) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                Text("Parts for \(vehicle.displayName)")
                    .font(.subheadline.weight(.medium))
                Text("Odomind opens a retailer's own search with what it knows about your vehicle. It does not hold prices or stock of its own.")
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                PrimaryActionButton(title: "Find “\(searchText)”", symbolName: "bag") {
                    router.homePath.append(JobRoute.parts(nil))
                }
                .accessibilityIdentifier("home.findParts")
            }
        }
    }

    // MARK: - Up next

    @ViewBuilder
    private func upNextSection(for vehicle: Vehicle) -> some View {
        let agenda = model.upNext(for: vehicle, limit: 4)

        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            SectionHeading(title: "Up next") {
                Button("Open calendar") {
                    router.selectedTab = .calendar
                }
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.accent)
                .accessibilityIdentifier("home.openCalendar")
            }

            WeekStrip { day in
                router.selectedTab = .calendar
                router.calendarSelectedDay = day
            }

            if agenda.isEmpty {
                Card {
                    UpNextEmptyState(vehicle: vehicle) {
                        router.selectedTab = .jobs
                    }
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(agenda) { evaluation in
                        AgendaRow(evaluation: evaluation) {
                            router.homePath.append(JobRoute.task(evaluation.planItemID))
                        } markDone: {
                            quickLog = QuickLogRequest(vehicleID: vehicle.id, planItemID: evaluation.planItemID)
                        }
                        if evaluation.id != agenda.last?.id {
                            Divider().overlay(Theme.Palette.separator)
                        }
                    }
                }
                .background(Theme.Palette.raised, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            }
        }
    }

    // MARK: - Actions and recent work

    @ViewBuilder
    private func actionsSection(for vehicle: Vehicle) -> some View {
        VStack(spacing: Theme.Spacing.small) {
            PrimaryActionButton(title: "Log service", symbolName: "checkmark.seal") {
                showingServiceLog = true
            }
            .accessibilityIdentifier("home.logService")

            PrimaryActionButton(title: "Update mileage", isProminent: false) {
                showingMileageEntry = true
            }
            .accessibilityIdentifier("home.updateMileage")
        }
    }

    @ViewBuilder
    private func recentSection(for vehicle: Vehicle) -> some View {
        let records = Array(model.serviceRecords(for: vehicle.id).prefix(3))
        if !records.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                SectionHeading(title: "Recent work") {
                    Button("See all") { router.selectedTab = .calendar }
                        .font(.subheadline)
                        .foregroundStyle(Theme.Palette.accent)
                }
                VStack(spacing: 0) {
                    ForEach(records) { record in
                        Button {
                            router.homePath.append(RecordRoute.record(record.id))
                        } label: {
                            RecentWorkRow(record: record)
                        }
                        .buttonStyle(.plain)
                        if record.id != records.last?.id {
                            Divider().overlay(Theme.Palette.separator)
                        }
                    }
                }
                .background(Theme.Palette.raised, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            }
        }
    }
}

/// What Home says when there is nothing to act on.
///
/// Never "you are all clear". Odomind knows what it has been told and nothing
/// else, and when a plan has no history the honest thing to say is that the
/// plan is ready and what would make it useful.
struct UpNextEmptyState: View {
    @Environment(AppModel.self) private var model
    let vehicle: Vehicle
    let browseJobs: () -> Void

    var body: some View {
        let evaluations = model.evaluations(for: vehicle.id)
        let unknown = evaluations.filter { $0.state == .historyUnknown || $0.state == .needsSetup }

        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            if evaluations.isEmpty {
                Text("No jobs tracked yet")
                    .font(.subheadline.weight(.medium))
                Text("Pick the maintenance you care about and Odomind will keep track of when it is next due.")
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Browse jobs", action: browseJobs)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.Palette.accent)
            } else if !unknown.isEmpty {
                Text("Your plan is ready")
                    .font(.subheadline.weight(.medium))
                Text("Add your last oil change when you know it and Odomind can work out when the next one is due. Until then it will not guess.")
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Set a starting point", action: browseJobs)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.Palette.accent)
                    .accessibilityIdentifier("home.setStartingPoint")
            } else {
                Text("Nothing due from your records")
                    .font(.subheadline.weight(.medium))
                Text("Keeping your mileage current is what keeps this accurate.")
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home.upNextEmpty")
    }
}

/// One actionable job on Home or in the calendar's agenda.
struct AgendaRow: View {
    @Environment(AppModel.self) private var model
    let evaluation: ScheduleEvaluation
    let open: () -> Void
    var markDone: (() -> Void)?

    var body: some View {
        HStack(spacing: Theme.Spacing.medium) {
            Button(action: open) {
                HStack(spacing: Theme.Spacing.medium) {
                    Image(systemName: evaluation.state.symbolName)
                        .foregroundStyle(evaluation.state.tint)
                        .frame(width: 22)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(evaluation.title)
                            .font(.body)
                            .foregroundStyle(Theme.Palette.primaryText)
                            .multilineTextAlignment(.leading)
                        if let detail = DueSummary.compactText(
                            for: evaluation, calendar: model.calendar, now: model.clock.now
                        ) {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(
                                    evaluation.state == .overdue ? Theme.Colors.overdue : Theme.Palette.secondaryText
                                )
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: Theme.Spacing.small)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("agenda.task.\(evaluation.definitionID)")
            .accessibilityLabel(Text(agendaLabel))

            if let markDone {
                // A checkmark opens a confirmation sheet. It never silently
                // records work: the date and the mileage both need saying.
                Button(action: markDone) {
                    Image(systemName: "checkmark.circle")
                        .font(.title3)
                        .frame(width: Theme.minimumTapTarget, height: Theme.minimumTapTarget)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Palette.accent)
                .accessibilityLabel(Text("Record \(evaluation.title) as done"))
                .accessibilityIdentifier("agenda.markDone.\(evaluation.definitionID)")
            }
        }
        .padding(.horizontal, Theme.Spacing.medium)
        .padding(.vertical, Theme.Spacing.small)
    }

    private var agendaLabel: String {
        let detail = DueSummary.text(for: evaluation, calendar: model.calendar, now: model.clock.now)
        return "\(evaluation.title). \(evaluation.state.displayName). \(detail)"
    }
}

/// A compact seven-day strip. Tapping a day opens Calendar there.
struct WeekStrip: View {
    @Environment(AppModel.self) private var model
    let select: (Date) -> Void

    var body: some View {
        let today = model.calendar.startOfDay(for: model.clock.now)
        let days = (0..<7).compactMap { model.calendar.date(byAdding: .day, value: $0, to: today) }

        HStack(spacing: Theme.Spacing.small) {
            ForEach(days, id: \.self) { day in
                let isToday = model.calendar.isDate(day, inSameDayAs: today)
                let count = model.calendarDayLoad(day)
                Button {
                    select(day)
                } label: {
                    VStack(spacing: 3) {
                        Text(Format.weekdayInitial(day, calendar: model.calendar))
                            .font(.caption2)
                            .foregroundStyle(Theme.Palette.secondaryText)
                        Text(Format.dayNumber(day, calendar: model.calendar))
                            .font(.subheadline.weight(isToday ? .bold : .regular))
                            .foregroundStyle(isToday ? Theme.Palette.onAccent : Theme.Palette.primaryText)
                            .frame(width: 30, height: 30)
                            .background(
                                isToday ? AnyShapeStyle(Theme.Palette.accent) : AnyShapeStyle(Color.clear),
                                in: Circle()
                            )
                        // A dot alone would be colour-only, so the label below
                        // carries the count for VoiceOver and the dot is
                        // decoration.
                        Circle()
                            .fill(count > 0 ? Theme.Palette.accent : Color.clear)
                            .frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: Theme.minimumTapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(dayLabel(day, isToday: isToday, count: count)))
            }
        }
        .padding(.vertical, Theme.Spacing.small)
        .padding(.horizontal, Theme.Spacing.small)
        .background(Theme.Palette.raised, in: RoundedRectangle(cornerRadius: Theme.Radius.tile))
    }

    private func dayLabel(_ day: Date, isToday: Bool, count: Int) -> String {
        var parts = [Format.longDate(day)]
        if isToday { parts.append("today") }
        parts.append(count == 0 ? "nothing scheduled" : "\(count) item\(count == 1 ? "" : "s")")
        return parts.joined(separator: ", ")
    }
}

/// A recently recorded visit.
struct RecentWorkRow: View {
    @Environment(AppModel.self) private var model
    let record: ServiceRecord

    var body: some View {
        HStack(spacing: Theme.Spacing.medium) {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.title)
                    .font(.body)
                    .foregroundStyle(Theme.Palette.primaryText)
                    .multilineTextAlignment(.leading)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)
            }
            Spacer(minLength: Theme.Spacing.small)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Palette.secondaryText)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Theme.Spacing.medium)
        .padding(.vertical, Theme.Spacing.medium)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        var parts = [Format.date(record.performedOn)]
        if let odometer = record.odometer { parts.append(Format.distance(odometer)) }
        if let cost = record.totalCost { parts.append(Format.money(cost)) }
        return parts.joined(separator: " · ")
    }
}
