import SwiftUI
import OdomindCore

/// A compact month, with a dot per kind of thing on a day.
///
/// Weeks start where the owner's locale says they start, month lengths come
/// from the calendar, and every date is anchored to the start of its day in the
/// current time zone — so a daylight-saving change moves nothing.
struct MonthGrid: View {
    @Environment(AppModel.self) private var model
    @Binding var visibleMonth: Date
    @Binding var selectedDay: Date

    var body: some View {
        let calendar = model.calendar
        let month = calendar.date(from: calendar.dateComponents([.year, .month], from: visibleMonth)) ?? visibleMonth
        let days = daysInGrid(for: month, calendar: calendar)
        let entriesByDay = entriesByDay()

        VStack(spacing: Theme.Spacing.medium) {
            HStack {
                Button { step(by: -1) } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: Theme.minimumTapTarget, height: Theme.minimumTapTarget)
                }
                .accessibilityLabel(Text("Previous month"))

                Spacer()
                Text(Format.monthAndYear(month, calendar: calendar))
                    .font(.headline)
                    .foregroundStyle(Theme.Palette.primaryText)
                    .accessibilityAddTraits(.isHeader)
                Spacer()

                Button { step(by: 1) } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: Theme.minimumTapTarget, height: Theme.minimumTapTarget)
                }
                .accessibilityLabel(Text("Next month"))
            }
            .foregroundStyle(Theme.Palette.accent)

            HStack(spacing: 0) {
                ForEach(weekdaySymbols(calendar: calendar), id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2)
                        .foregroundStyle(Theme.Palette.secondaryText)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 4) {
                ForEach(days, id: \.self) { day in
                    DayCell(
                        day: day,
                        isInMonth: calendar.isDate(day, equalTo: month, toGranularity: .month),
                        isToday: calendar.isDate(day, inSameDayAs: calendar.startOfDay(for: model.clock.now)),
                        isSelected: calendar.isDate(day, inSameDayAs: selectedDay),
                        kinds: entriesByDay[day].map { Set($0.map(\.kind)) } ?? []
                    ) {
                        selectedDay = day
                    }
                }
            }

            Button("Today") {
                let today = calendar.startOfDay(for: model.clock.now)
                selectedDay = today
                visibleMonth = today
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.Palette.accent)
            .buttonStyle(.tappableText)
            .accessibilityIdentifier("calendar.today")
        }
        .padding(Theme.Spacing.medium)
        .background(Theme.Palette.raised, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    private func step(by months: Int) {
        guard let next = model.calendar.date(byAdding: .month, value: months, to: visibleMonth) else { return }
        visibleMonth = next
    }

    private func entriesByDay() -> [Date: [CalendarEntry]] {
        Dictionary(grouping: model.allCalendarEntries(), by: { model.calendar.startOfDay(for: $0.date) })
    }

    /// Weekday headers rotated to the locale's first weekday.
    private func weekdaySymbols(calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        guard symbols.count == 7, first >= 0, first < 7 else { return symbols }
        return Array(symbols[first...] + symbols[..<first])
    }

    /// Whole weeks covering the month, so the grid never has a ragged edge.
    private func daysInGrid(for month: Date, calendar: Calendar) -> [Date] {
        guard let range = calendar.range(of: .day, in: .month, for: month),
              let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: month))
        else { return [] }

        let leading = (calendar.component(.weekday, from: firstOfMonth) - calendar.firstWeekday + 7) % 7
        guard let start = calendar.date(byAdding: .day, value: -leading, to: firstOfMonth) else { return [] }

        let total = leading + range.count
        let weeks = Int((Double(total) / 7).rounded(.up))
        return (0..<(weeks * 7)).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }
}

/// One square.
private struct DayCell: View {
    let day: Date
    let isInMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let kinds: Set<CalendarEntryKind>
    let select: () -> Void

    @Environment(AppModel.self) private var model
    /// See the note beside the day number below.
    @ScaledMetric(relativeTo: .subheadline) private var dayCircle: CGFloat = 30

    var body: some View {
        Button(action: select) {
            VStack(spacing: 3) {
                Text(Format.dayNumber(day, calendar: model.calendar))
                    .font(.subheadline.weight(isToday ? .bold : .regular))
                    .foregroundStyle(numberColour)
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
                    .background(background, in: Circle())
                    .overlay {
                        // Today keeps a ring even when another day is
                        // selected, so "today" is never conveyed by fill alone.
                        if isToday && !isSelected {
                            Circle().strokeBorder(Theme.Palette.accent, lineWidth: 1.5)
                        }
                    }

                HStack(spacing: 2) {
                    ForEach(CalendarEntryKind.allCases.filter { kinds.contains($0) }, id: \.self) { kind in
                        Circle()
                            .fill(kind.tint)
                            .frame(width: 4, height: 4)
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: Theme.minimumTapTarget)
            .opacity(isInMonth ? 1 : 0.35)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var numberColour: Color {
        if isSelected { return Theme.Palette.onAccent }
        return Theme.Palette.primaryText
    }

    private var background: AnyShapeStyle {
        isSelected ? AnyShapeStyle(Theme.Palette.accent) : AnyShapeStyle(Color.clear)
    }

    private var label: String {
        var parts = [Format.longDate(day)]
        if isToday { parts.append("today") }
        if kinds.isEmpty {
            parts.append("nothing scheduled")
        } else {
            parts.append(
                CalendarEntryKind.allCases
                    .filter { kinds.contains($0) }
                    .map(\.displayName)
                    .joined(separator: ", ")
            )
        }
        return parts.joined(separator: ", ")
    }
}
