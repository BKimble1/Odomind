import SwiftUI
import OdomindCore

/// Calendar: what happened, what is booked, and what is coming.
///
/// Build 1 had a History tab that was a large empty state above a row of
/// filters. Past and future are the same question asked in two directions, so
/// they are one screen now. The gear lives here, at the top right, because the
/// brief asked for it and because Garage should be a garage rather than a
/// settings menu.
struct CalendarView: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationRouter.self) private var router

    @State private var visibleMonth = Date()
    @State private var searchText = ""
    @State private var showsList = false
    @State private var newAppointment: AppointmentDraft?
    @State private var batchExport = false

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.calendarPath) {
            Group {
                if model.selectedVehicle != nil {
                    content
                } else {
                    NoVehicleView()
                }
            }
            .navigationTitle("Calendar")
            .background(Theme.Palette.page)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { VehiclePickerBar() }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showsList.toggle()
                        } label: {
                            Label(
                                showsList ? "Show the month" : "Show as a list",
                                systemImage: showsList ? "calendar" : "list.bullet"
                            )
                        }
                        .accessibilityIdentifier("calendar.toggleList")

                        Button {
                            if let vehicleID = model.selectedVehicleID {
                                newAppointment = AppointmentDraft(vehicleID: vehicleID, scheduledOn: selectedDay)
                            }
                        } label: {
                            Label("Add an appointment", systemImage: "calendar.badge.plus")
                        }

                        Divider()

                        Button {
                            router.calendarPath.append(RecordRoute.export)
                        } label: {
                            Label("Export service history", systemImage: "square.and.arrow.up")
                        }
                        .accessibilityIdentifier("calendar.export")
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .accessibilityLabel(Text("More"))
                            .accessibilityIdentifier("calendar.menu")
                    }

                    NavigationLink(value: SettingsRoute.settings) {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(Text("Settings"))
                    .accessibilityIdentifier("calendar.settings")
                }
            }
            .odomindDestinations()
            .searchable(text: $searchText, prompt: "Search service")
            .sheet(item: $newAppointment) { draft in
                AppointmentEditor(draft: draft)
            }
            .sheet(isPresented: $batchExport) {
                CalendarExportReview()
            }
            .onAppear {
                if let requested = router.calendarSelectedDay {
                    visibleMonth = requested
                    router.calendarSelectedDay = nil
                }
            }
            .onChange(of: router.calendarSelectedDay) { _, newValue in
                guard let newValue else { return }
                selectedDay = model.calendar.startOfDay(for: newValue)
                visibleMonth = newValue
                showsList = false
                router.calendarSelectedDay = nil
            }
        }
    }

    @State private var selectedDay = Date()

    @ViewBuilder
    private var content: some View {
        if !searchText.isEmpty {
            searchResults
        } else if showsList {
            AgendaListView(select: openEntry)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.large) {
                    MonthGrid(
                        visibleMonth: $visibleMonth,
                        selectedDay: $selectedDay
                    )

                    CalendarLegend()

                    daySection

                    unscheduledSection

                    exportSection
                }
                .padding(Theme.Spacing.large)
            }
            .refreshable {
                model.refresh()
                await model.syncReminders()
            }
        }
    }

    @ViewBuilder
    private var daySection: some View {
        let entries = model.calendarEntries(on: selectedDay)
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            SectionHeading(title: Format.longDate(selectedDay)) {
                Button {
                    if let vehicleID = model.selectedVehicleID {
                        newAppointment = AppointmentDraft(vehicleID: vehicleID, scheduledOn: selectedDay)
                    }
                } label: {
                    Label("Add appointment", systemImage: "plus")
                        .labelStyle(.iconOnly)
                        .frame(width: Theme.minimumTapTarget, height: Theme.minimumTapTarget)
                }
                .foregroundStyle(Theme.Palette.accent)
                .accessibilityLabel(Text("Add an appointment on this day"))
                .accessibilityIdentifier("calendar.addAppointment")
            }

            if entries.isEmpty {
                Card {
                    Text("Nothing on this day.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Palette.secondaryText)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(entries) { entry in
                        CalendarEntryRow(entry: entry) { openEntry(entry) }
                        if entry.id != entries.last?.id {
                            Divider().overlay(Theme.Palette.separator)
                        }
                    }
                }
                .background(Theme.Palette.raised, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            }
        }
    }

    @ViewBuilder
    private var unscheduledSection: some View {
        let unscheduled = model.unscheduledCalendarItems()
        if !unscheduled.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                SectionHeading("Mileage based · date not yet estimated")
                Card {
                    VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                        Text("These are due at a mileage, and Odomind does not yet know enough about how far you drive to put a date on them.")
                            .font(.footnote)
                            .foregroundStyle(Theme.Palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(unscheduled) { evaluation in
                            Button {
                                router.calendarPath.append(JobRoute.task(evaluation.planItemID))
                            } label: {
                                HStack {
                                    Text(evaluation.title)
                                        .foregroundStyle(Theme.Palette.primaryText)
                                    Spacer()
                                    if let odometer = evaluation.nextDueOdometer {
                                        Text(Format.distance(odometer))
                                            .font(.caption)
                                            .foregroundStyle(Theme.Palette.secondaryText)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("calendar.unscheduled.\(evaluation.definitionID)")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var exportSection: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                Text("Apple Calendar")
                    .font(.subheadline.weight(.medium))
                Text("Odomind can add upcoming items to your calendar. You review what gets added, and it is a copy — Odomind does not keep it in step unless you turn on managed updates.")
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Add upcoming items…") { batchExport = true }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.Palette.accent)
                    .buttonStyle(.tappableText)
                    .accessibilityIdentifier("calendar.batchExport")
            }
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        let needle = searchText.lowercased()
        let matches = model.allCalendarEntries().filter { $0.title.lowercased().contains(needle) }
        if matches.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            List {
                ForEach(matches) { entry in
                    Button { openEntry(entry) } label: {
                        CalendarEntryRow(entry: entry, showsDate: true) { openEntry(entry) }
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
        }
    }

    private func openEntry(_ entry: CalendarEntry) {
        if let recordID = entry.recordID {
            router.calendarPath.append(RecordRoute.record(recordID))
        } else if let planItemID = entry.planItemID {
            router.calendarPath.append(JobRoute.task(planItemID))
        } else if let appointmentID = entry.appointmentID,
                  let appointment = model.snapshot.appointments.first(where: { $0.id == appointmentID }) {
            newAppointment = AppointmentDraft(appointment: appointment)
        }
    }
}

/// The legend. Icons and words, never colour alone.
struct CalendarLegend: View {
    var body: some View {
        // Wrapping rather than an HStack: four labelled kinds do not fit on
        // one line on a narrow phone, and an HStack answers that by
        // truncating the words — which is exactly the signal that keeps this
        // legend from being colour alone.
        WrappingHStack {
            ForEach(CalendarEntryKind.allCases, id: \.self) { kind in
                HStack(spacing: Theme.Spacing.tight) {
                    Image(systemName: kind.symbolName)
                        .imageScale(.small)
                        .foregroundStyle(kind.tint)
                    Text(kind.displayName)
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.secondaryText)
                        .fixedSize()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Legend: done, appointment, due, estimated."))
    }
}

extension CalendarEntryKind {
    var tint: Color {
        switch self {
        case .completed: return Theme.Colors.done
        case .appointment: return Theme.Palette.accent
        case .due: return Theme.Colors.caution
        case .projected: return Theme.Palette.secondaryText
        }
    }
}

/// One row in a day's agenda.
struct CalendarEntryRow: View {
    @Environment(AppModel.self) private var model
    let entry: CalendarEntry
    var showsDate: Bool = false
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: Theme.Spacing.medium) {
                Image(systemName: entry.kind.symbolName)
                    .foregroundStyle(entry.kind.tint)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(.body)
                        .foregroundStyle(Theme.Palette.primaryText)
                        .multilineTextAlignment(.leading)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.secondaryText)
                        .multilineTextAlignment(.leading)
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
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        // The kind is spoken, so a screen reader is never left to infer it
        // from an icon's colour.
        .accessibilityLabel(Text("\(entry.kind.displayName). \(entry.title). \(detail)"))
        .accessibilityIdentifier("calendar.entry.\(entry.kind.rawValue)")
    }

    private var detail: String {
        var parts: [String] = []
        if showsDate { parts.append(Format.date(entry.date)) }
        parts.append(entry.kind.displayName)
        if let subtitle = entry.subtitle { parts.append(subtitle) }
        if entry.kind == .projected {
            parts.append("estimated from how far you usually drive")
        }
        return parts.joined(separator: " · ")
    }
}

/// The flat list, for anyone who would rather read than scan a grid.
struct AgendaListView: View {
    @Environment(AppModel.self) private var model
    let select: (CalendarEntry) -> Void

    var body: some View {
        let entries = model.allCalendarEntries()
        if entries.isEmpty {
            ContentUnavailableView {
                Label("Nothing recorded yet", systemImage: "calendar")
            } description: {
                Text("Work you record and appointments you add will appear here, alongside what Odomind expects to come up.")
            }
        } else {
            List {
                ForEach(grouped(entries)) { month in
                    Section(Format.monthAndYear(month.start, calendar: model.calendar)) {
                        ForEach(month.entries) { entry in
                            CalendarEntryRow(entry: entry, showsDate: true) { select(entry) }
                                .listRowInsets(EdgeInsets())
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private func grouped(_ entries: [CalendarEntry]) -> [CalendarMonthGroup] {
        var buckets: [Date: [CalendarEntry]] = [:]
        for entry in entries {
            let components = model.calendar.dateComponents([.year, .month], from: entry.date)
            guard let month = model.calendar.date(from: components) else { continue }
            buckets[month, default: []].append(entry)
        }
        return buckets.keys.sorted(by: >).map {
            CalendarMonthGroup(start: $0, entries: buckets[$0] ?? [])
        }
    }
}

/// A month's worth of entries. A named type rather than a tuple, because
/// `ForEach` needs an identity and Swift has no key path into a tuple element.
struct CalendarMonthGroup: Identifiable, Hashable {
    var id: Date { start }
    var start: Date
    var entries: [CalendarEntry]
}
