import LucideSwift
import SwiftUI

/// The day the list shows, with an arrow on each side. Clicking the date opens the calendar.
struct DayControl: View {
    /// A long date like "Wed, 30.11" fits. The width stays fixed so the arrows don't move under your pointer as you step.
    private static let labelWidth: CGFloat = 62

    @ObservedObject var history: HistoryModel

    var body: some View {
        HStack(spacing: 0) {
            arrow(.chevronLeft, help: "Previous day", enabled: history.hasEarlierDay) { _ = history.showEarlierDay() }
            Button {
                withAnimation(Theme.Motion.section) { history.showsCalendar.toggle() }
            } label: {
                Text(RecentTime.dayLabel(for: history.day, now: Date()))
                    .font(.ui(12, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: Self.labelWidth, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable(0.97))
            .help("Open the calendar")
            arrow(.chevronRight, help: "Next day", enabled: history.hasLaterDay) { _ = history.showLaterDay() }
        }
        .padding(2)
        .background(history.showsCalendar ? Theme.selectedStrong : Theme.selected, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .animation(Theme.Motion.hover, value: history.showsCalendar)
    }

    private func arrow(_ icon: LucideIconName, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        IconButton(icon: icon, help: help, size: 13, action: action)
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.35)
    }
}

/// One month with room for six weeks, so moving between months doesn't resize the panel. Only days you dictated on can be picked.
struct DayCalendar: View {
    @ObservedObject var history: HistoryModel
    @State private var month: Date

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    init(history: HistoryModel) {
        self.history = history
        _month = State(initialValue: CalendarMonth.start(of: history.day))
    }

    private var weekdays: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private var canGoBack: Bool { history.days.oldest.map { CalendarMonth.start(of: $0) < month } ?? false }
    private var canGoForward: Bool { month < CalendarMonth.start(of: Date()) }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 0) {
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.ui(13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(.leading, 6)
                Spacer(minLength: 8)
                monthButton(.chevronLeft, help: "Previous month", enabled: canGoBack, by: -1)
                monthButton(.chevronRight, help: "Next month", enabled: canGoForward, by: 1)
            }
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Array(weekdays.enumerated()), id: \.offset) { _, weekday in
                    Text(weekday)
                        .font(.ui(11))
                        .foregroundStyle(Theme.inkTertiary)
                        .frame(height: 20)
                }
                ForEach(Array(CalendarMonth.cells(of: month).enumerated()), id: \.offset) { _, day in
                    if let day { cell(day) } else { Color.clear.frame(height: 28) }
                }
            }
        }
        .groupCard(padding: 8)
    }

    private func monthButton(_ icon: LucideIconName, help: String, enabled: Bool, by months: Int) -> some View {
        IconButton(icon: icon, help: help, size: 13) {
            month = calendar.date(byAdding: .month, value: months, to: month) ?? month
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }

    private func cell(_ day: Date) -> some View {
        let isToday = calendar.isDateInToday(day)
        return DayCell(
            number: calendar.component(.day, from: day),
            date: day,
            canPick: isToday || history.days.contains(day),
            isSelected: history.day == day,
            isToday: isToday,
            action: { withAnimation(Theme.Motion.section) { history.pick(day) } }
        )
    }
}

private struct DayCell: View {
    let number: Int
    let date: Date
    let canPick: Bool
    let isSelected: Bool
    let isToday: Bool
    let action: () -> Void
    @State private var hovering = false

    private var ink: Color {
        if isSelected { return .white }
        if !canPick { return Theme.inkTertiary }
        return isToday ? Theme.accent : Theme.ink
    }

    private var fill: Color {
        if isSelected { return Theme.accent }
        return hovering && canPick ? Theme.selected : .clear
    }

    var body: some View {
        Button(action: action) {
            Text("\(number)")
                .font(.ui(12, weight: isToday || isSelected ? .semibold : .regular))
                .foregroundStyle(ink)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(fill, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable(0.97))
        .disabled(!canPick)
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
        .onHover { hovering = $0 }
        .animation(Theme.Motion.hover, value: hovering)
    }
}
