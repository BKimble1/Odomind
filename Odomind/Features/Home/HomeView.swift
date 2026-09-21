import SwiftUI
import OdomindCore

/// Home: which vehicle, what is coming, and the two things an owner actually
/// does — record mileage and record work.
///
/// The hierarchy is the one Build 3 asked for, top to bottom: the vehicle at
/// upper left and the shopping area at upper right, then one compact overview
/// with a single way to edit mileage, then one search field with an explicit
/// Jobs/Parts choice, then the week and a short agenda. "Log service" is
/// pinned above the tab bar so the primary action is never the thing you have
/// to scroll past four due jobs to reach.
///
/// What is gone since Build 2: the card that repeated the vehicle's name under
/// the navigation bar that already said it, the second "Update mileage" button
/// that did the same thing as the pencil two rows above it, and the rounded
/// plate drawn around every one of five sections. Rows sit on the page and are
/// separated by hairlines, which is what a list looks like.
struct HomeView: View {
    /// Shown only to somebody who already had a garage before these questions
    /// existed. See `AppModel.shouldOfferPermissionCatchUp`.
    @State private var showingPermissionCatchUp = false

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

        var placeholder: String {
            switch self {
            case .jobs: return "Search jobs — oil, brakes, tires"
            case .parts: return "Search parts — oil filter, wiper blade"
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
            // White in light, near-black in dark. With the section plates gone
            // the rows need a surface of their own to sit on, and the page
            // grey underneath a plateless list only looks unfinished.
            .background(Theme.Palette.raised)
            .toolbar {
                // Vehicle upper left, shopping area upper right — the two
                // standing choices every screen below depends on.
                ToolbarItem(placement: .topBarLeading) { VehiclePickerBar() }
                ToolbarItem(placement: .topBarTrailing) { ShoppingLocationControl() }
            }
            .odomindDestinations()
            .sheet(isPresented: $showingMileageEntry) {
                if let vehicle = model.selectedVehicle { MileageEntrySheet(vehicle: vehicle) }
            }
            .sheet(isPresented: $showingPermissionCatchUp) {
                PermissionSetupView {
                    model.markPermissionSetupSeen()
                    showingPermissionCatchUp = false
                }
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
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                MileageOverview(vehicle: vehicle) { showingMileageEntry = true }
                    .padding(.horizontal, Theme.Spacing.large)

                searchSection(for: vehicle)

                if searchText.isEmpty {
                    upNextSection(for: vehicle)
                    recentSection(for: vehicle)
                }

                if vehicle.isDemo, let disclaimer = model.demoDisclaimer {
                    QuietNote(text: disclaimer, symbolName: "exclamationmark.triangle")
                        .padding(.horizontal, Theme.Spacing.large)
                }

                // Somebody upgrading already has a garage and has never been
                // asked these. One quiet row, dismissed for good either way —
                // not the whole welcome sequence replayed at them.
                if model.shouldOfferPermissionCatchUp {
                    permissionCatchUpRow
                        .padding(.horizontal, Theme.Spacing.large)
                }
            }
            .padding(.vertical, Theme.Spacing.large)
        }
        .scrollDismissesKeyboard(.interactively)
        // The one primary action, kept where a thumb is and where four due
        // jobs cannot push it off the bottom of the screen. `safeAreaInset`
        // is what keeps it clear of the tab bar and above the keyboard, and
        // it insets the scroll content so the last row is still reachable.
        .safeAreaInset(edge: .bottom, spacing: 0) { logServiceBar }
        .refreshable {
            model.refresh()
            await model.syncReminders()
        }
    }

    private var logServiceBar: some View {
        VStack(spacing: 0) {
            Divider().overlay(Theme.Palette.separator)
            PrimaryActionButton(title: "Log service", symbolName: "checkmark.seal") {
                showingServiceLog = true
            }
            .accessibilityIdentifier("home.logService")
            .padding(.horizontal, Theme.Spacing.large)
            .padding(.top, Theme.Spacing.medium)
            .padding(.bottom, Theme.Spacing.small)
        }
        .background(.bar)
    }

    @ViewBuilder
    private var permissionCatchUpRow: some View {
        Button {
            showingPermissionCatchUp = true
        } label: {
            HStack(spacing: Theme.Spacing.medium) {
                Image(systemName: "bell.badge")
                    .foregroundStyle(Theme.Palette.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Finish setting up")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.Palette.primaryText)
                    Text("Reminders and nearby shops are still off.")
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.secondaryText)
                }
                Spacer(minLength: Theme.Spacing.small)
                Button("Not now") { model.markPermissionSetupSeen() }
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .buttonStyle(.tappableText)
                    .accessibilityIdentifier("home.permissionsDismiss")
            }
            .padding(Theme.Spacing.medium)
            .background(Theme.Palette.recessed, in: RoundedRectangle(cornerRadius: Theme.Radius.tile))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.permissionsCatchUp")
    }

    // MARK: - Search

    @ViewBuilder
    private func searchSection(for vehicle: Vehicle) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            HStack(spacing: Theme.Spacing.small) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .accessibilityHidden(true)
                TextField(searchScope.placeholder, text: $searchText)
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
            .background(Theme.Palette.recessed, in: RoundedRectangle(cornerRadius: Theme.Radius.tile))
            .padding(.horizontal, Theme.Spacing.large)

            // Always visible, not revealed on the first keystroke: the choice
            // between a job and a part is the thing that decides what typing
            // will do, so it has to be legible before you type. The query
            // survives the switch, which is why this is one field and not two
            // screens.
            Picker("What to search", selection: $searchScope) {
                ForEach(SearchScope.allCases, id: \.self) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("home.searchScope")
            .padding(.horizontal, Theme.Spacing.large)

            // The gutter is applied per element rather than to the whole
            // stack, because result rows carry their own and would otherwise
            // be indented twice.
            if !searchText.isEmpty {
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
            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                Text("Nothing matching “\(searchText)”")
                    .font(.subheadline.weight(.medium))
                Text("Try a simpler word — “oil”, “tires”, “brakes” — or add it as your own job.")
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Create a custom job") { router.homePath.append(JobRoute.customTask) }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.Palette.accent)
                    .buttonStyle(.tappableText)
            }
            .padding(.horizontal, Theme.Spacing.large)
        } else {
            let shown = Array(results.prefix(8))
            SeparatedRows(shown) { result in
                JobSearchRow(result: result) {
                    // An untracked job opens that job, not the library. Build
                    // 2 pushed the whole catalog here and threw the query
                    // away, so tapping "brake fluid" produced ninety rows and
                    // the owner had to find theirs a second time.
                    if let planItemID = result.planItemID {
                        router.homePath.append(JobRoute.task(planItemID))
                    } else {
                        router.homePath.append(JobRoute.untracked(result.definitionID))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func partResults(for vehicle: Vehicle) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            Text("Odomind opens a retailer's own search with what it knows about \(vehicle.displayName). It does not hold prices or stock of its own.")
                .font(.footnote)
                .foregroundStyle(Theme.Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            PrimaryActionButton(title: "Find “\(searchText)”", isProminent: false, symbolName: "bag") {
                router.homePath.append(JobRoute.parts(PartsDestination(query: searchText)))
            }
            .accessibilityIdentifier("home.findParts")
        }
        .padding(.horizontal, Theme.Spacing.large)
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
                .buttonStyle(.tappableText)
                .accessibilityIdentifier("home.openCalendar")
            }
            .padding(.horizontal, Theme.Spacing.large)

            WeekStrip { day in
                router.selectedTab = .calendar
                router.calendarSelectedDay = day
            }
            .padding(.horizontal, Theme.Spacing.large)

            if agenda.isEmpty {
                UpNextEmptyState(vehicle: vehicle) {
                    router.selectedTab = .jobs
                }
                .padding(.horizontal, Theme.Spacing.large)
            } else {
                SeparatedRows(agenda) { evaluation in
                    AgendaRow(evaluation: evaluation) {
                        router.homePath.append(JobRoute.task(evaluation.planItemID))
                    } markDone: {
                        quickLog = QuickLogRequest(vehicleID: vehicle.id, planItemID: evaluation.planItemID)
                    }
                }
            }
        }
    }

    // MARK: - Recent work

    @ViewBuilder
    private func recentSection(for vehicle: Vehicle) -> some View {
        let records = Array(model.serviceRecords(for: vehicle.id).prefix(3))
        if !records.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                SectionHeading(title: "Recent work") {
                    Button("See all") { router.selectedTab = .calendar }
                        .font(.subheadline)
                        .foregroundStyle(Theme.Palette.accent)
                        .buttonStyle(.tappableText)
                }
                .padding(.horizontal, Theme.Spacing.large)

                SeparatedRows(records) { record in
                    Button {
                        router.homePath.append(RecordRoute.record(record.id))
                    } label: {
                        RecentWorkRow(record: record)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// One compact vehicle overview: the mileage, when it was read, and the one
/// way to change it.
///
/// The vehicle's name is not here on purpose — the navigation bar above says
/// it, and Build 2 printed it twice within forty points. What is left is the
/// number the rest of the screen is calculated from, at a size that says so.
struct MileageOverview: View {
    @Environment(AppModel.self) private var model
    let vehicle: Vehicle
    let updateMileage: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.medium) {
            VStack(alignment: .leading, spacing: 2) {
                if let reading = model.latestReading(for: vehicle.id) {
                    Text(Format.distance(reading.value))
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Theme.Palette.primaryText)
                        .accessibilityIdentifier("home.odometer")
                        .accessibilityLabel(Text("Recorded odometer \(Format.distance(reading.value))"))
                    Text(recordedText(reading))
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.secondaryText)
                } else {
                    Text("No mileage yet")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Theme.Palette.primaryText)
                        .accessibilityIdentifier("home.odometer")
                    Text("Odomind needs one reading before it can work out what is due.")
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: Theme.Spacing.small)

            Button("Update", action: updateMileage)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.Palette.accent)
                .buttonStyle(.tappableText)
                .accessibilityLabel(Text("Update mileage"))
                .accessibilityIdentifier("home.updateMileage")
        }
        .accessibilityElement(children: .contain)
    }

    private func recordedText(_ reading: OdometerReading) -> String {
        let days = DateSupport.dayCount(from: reading.recordedOn, to: model.clock.now, in: model.calendar)
        switch days {
        case ..<0: return "Recorded \(Format.date(reading.recordedOn))"
        case 0: return "Recorded today"
        case 1: return "Recorded yesterday"
        default: return "Recorded \(days) days ago"
        }
    }
}

/// A run of rows with a hairline between them and nothing around them.
///
/// The replacement for wrapping every list on Home in its own rounded plate.
/// The separator is inset to the content margin so it reads as a list rather
/// than a full-bleed rule across the screen.
struct SeparatedRows<Element: Identifiable, Row: View>: View {
    private let elements: [Element]
    private let row: (Element) -> Row

    init(_ elements: [Element], @ViewBuilder row: @escaping (Element) -> Row) {
        self.elements = elements
        self.row = row
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(elements) { element in
                row(element)
                if element.id != elements.last?.id {
                    Divider()
                        .overlay(Theme.Palette.separator)
                        .padding(.leading, Theme.Spacing.large)
                }
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
                    .buttonStyle(.tappableText)
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
                    .buttonStyle(.tappableText)
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.medium)
        .background(Theme.Palette.recessed, in: RoundedRectangle(cornerRadius: Theme.Radius.tile))
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
        .padding(.horizontal, Theme.Spacing.large)
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

    /// See the note beside the day number below.
    @ScaledMetric(relativeTo: .subheadline) private var dayCircle: CGFloat = 30

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
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            // Scales with the text and stops at a size seven of
                            // them still fit across a phone; the number shrinks
                            // inside it rather than truncating. At AccessibilityL a
                            // subheadline is about 34pt, so a fixed 30pt circle
                            // turned every date on the week strip into an ellipsis —
                            // including today's, inside the filled circle.
                            .frame(
                                width: min(dayCircle, Theme.minimumTapTarget),
                                height: min(dayCircle, Theme.minimumTapTarget)
                            )
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
        .padding(.horizontal, Theme.Spacing.large)
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
