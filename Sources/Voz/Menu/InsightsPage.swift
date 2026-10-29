import SwiftUI

struct InsightsPage: View {
    @ObservedObject var model: StatsModel
    @ObservedObject var settings: AppSettings
    let back: () -> Void
    @State private var period = StatsPeriod.week
    @State private var revealed = false

    private var stats: PeriodStats { model.stats[period] }
    private var loaded: Bool { !model.stats.days.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageBar(title: "Insights", back: back)
            if !settings.starPromptDismissed, model.stats[.all].words >= StarPromptCard.threshold {
                StarPromptCard(words: model.stats[.all].words) {
                    withAnimation(Theme.Motion.section) { settings.starPromptDismissed = true }
                }
                .transition(.opacity)
            }
            StreakSection(stats: model.stats, revealed: revealed)
            VStack(alignment: .leading, spacing: 16) {
                TabBar(tabs: StatsPeriod.allCases, selection: $period)
                WordsHeadline(stats: stats)
                HStack(alignment: .top, spacing: Theme.Spacing.item) {
                    PaceGauge(wordsPerMinute: stats.wordsPerMinute, revealed: revealed)
                    TimeSaved(stats: stats, revealed: revealed)
                }
                if !stats.topApps.isEmpty { TopApps(apps: stats.topApps) }
            }
            .animation(Theme.Motion.section, value: period)
        }
        .animation(Theme.Motion.section, value: model.stats)
        .onAppear { revealed = loaded }
        .onChange(of: loaded) { _, loaded in revealed = loaded }
    }
}

private extension Animation {
    static let reveal = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.45)
    static let revealColumn = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.3)
}

private struct StreakSection: View {
    let stats: UsageStats
    let revealed: Bool
    @State private var hovered: WordBucket?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(stats.streak.formatted())
                    .font(.display(32))
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
                Text("day streak")
                    .font(.ui(13))
                    .foregroundStyle(Theme.inkSecondary)
                Spacer(minLength: 0)
                if stats.longestStreak > 0 {
                    Text("Longest \(stats.longestStreak) \(stats.longestStreak == 1 ? "day" : "days")")
                        .font(.meta)
                        .monospacedDigit()
                        .foregroundStyle(Theme.inkTertiary)
                }
            }
            ActivityGrid(days: stats.days, revealed: revealed, hovered: $hovered)
            Text(caption)
                .font(.meta)
                .monospacedDigit()
                .foregroundStyle(hovered == nil ? Theme.inkSecondary : Theme.ink)
        }
    }

    private var dictatedToday: Bool { (stats.days.last?.words ?? 0) > 0 }

    private var caption: String {
        if let hovered {
            let words = hovered.words == 1 ? "1 word" : "\(hovered.words.formatted()) words"
            return "\(hovered.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())), \(words)"
        }
        if dictatedToday { return "You dictated today." }
        if stats.streak > 0 { return "Dictate today to keep your streak." }
        return "Dictate today to start a streak."
    }
}

private struct ActivityGrid: View {
    private static let cell: CGFloat = 10
    private static let spacing: CGFloat = 3

    let days: [WordBucket]
    let revealed: Bool
    @Binding var hovered: WordBucket?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var weeks: [[WordBucket]] {
        stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
    }

    private var busiest: Int { max(days.map(\.words).max() ?? 0, 1) }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { column, week in
                VStack(spacing: Self.spacing) {
                    Color.clear
                        .frame(width: Self.cell, height: 14)
                        .overlay(alignment: .topLeading) { monthLabel(for: week) }
                    ForEach(week) { day in
                        DayCell(level: level(of: day), isToday: day == days.last, isHovered: day == hovered, size: Self.cell)
                            .onHover { inside in
                                if inside { hovered = day } else if hovered == day { hovered = nil }
                            }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .opacity(revealed ? 1 : 0)
                .scaleEffect(revealed || reduceMotion ? 1 : 0.8, anchor: .bottom)
                .animation(.revealColumn.delay(Double(column) * 0.01), value: revealed)
            }
        }
        .frame(height: 14 + 7 * Self.cell + 7 * Self.spacing, alignment: .top)
    }

    @ViewBuilder
    private func monthLabel(for week: [WordBucket]) -> some View {
        if let first = week.first(where: { Calendar.current.component(.day, from: $0.start) == 1 }) {
            Text(first.start.formatted(.dateTime.month(.abbreviated)))
                .font(.ui(11))
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize()
        }
    }

    private func level(of day: WordBucket) -> Int {
        guard day.words > 0 else { return 0 }
        return min(Int((4 * Double(day.words) / Double(busiest)).rounded(.up)), 4)
    }
}

private struct DayCell: View {
    let level: Int
    let isToday: Bool
    let isHovered: Bool
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(level == 0 ? Theme.selected : Theme.accent.opacity([0, 0.32, 0.55, 0.78, 1][level]))
            .overlay {
                if isToday || isHovered {
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .strokeBorder(isHovered ? Theme.ink : Theme.inkTertiary, lineWidth: 1)
                }
            }
            .frame(width: size, height: size)
            .contentShape(Rectangle())
    }
}

private struct WordsHeadline: View {
    let stats: PeriodStats

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(stats.words.formatted())
                .font(.display(32))
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
            Text(caption)
                .font(.meta)
                .monospacedDigit()
                .foregroundStyle(Theme.inkSecondary)
                .contentTransition(.numericText())
        }
    }

    private var caption: String {
        let words = stats.words == 1 ? "word dictated" : "words dictated"
        guard stats.fixes > 0 else { return words }
        return "\(words), \(stats.fixes.formatted()) \(stats.fixes == 1 ? "filler" : "fillers") removed"
    }
}

private struct PaceGauge: View {
    private static let maximum = 200.0
    private static let lineWidth: CGFloat = 7

    let wordsPerMinute: Double?
    let revealed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fraction: Double { min((wordsPerMinute ?? 0) / Self.maximum, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Speaking pace")
            ZStack(alignment: .bottom) {
                HalfArc().stroke(Theme.selected, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                HalfArc()
                    .trim(from: 0, to: revealed ? fraction : 0)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                TypingTick(fraction: PeriodStats.typingWordsPerMinute / Self.maximum, lineWidth: Self.lineWidth)
                VStack(spacing: 0) {
                    Text(wordsPerMinute.map { Int($0.rounded()).formatted() } ?? "–")
                        .font(.display(22))
                        .foregroundStyle(Theme.ink)
                        .contentTransition(.numericText())
                    Text("wpm")
                        .font(.ui(11))
                        .foregroundStyle(Theme.inkTertiary)
                }
                .offset(y: 4)
            }
            .padding(.horizontal, Self.lineWidth / 2)
            .aspectRatio(2, contentMode: .fit)
            Text(comparison)
                .font(.meta)
                .monospacedDigit()
                .foregroundStyle(Theme.inkSecondary)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduceMotion ? nil : .reveal, value: revealed)
    }

    private var comparison: String {
        guard let wordsPerMinute else { return "Measured after you dictate" }
        let ratio = wordsPerMinute / PeriodStats.typingWordsPerMinute
        return "\(ratio.formatted(.number.precision(.fractionLength(1))))× typing speed"
    }
}

private struct HalfArc: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.addArc(center: CGPoint(x: rect.midX, y: rect.maxY), radius: rect.width / 2, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        }
    }
}

private struct TypingTick: View {
    let fraction: Double
    let lineWidth: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let radius = proxy.size.width / 2
            let angle = Angle.degrees(180 + 180 * fraction)
            Capsule()
                .fill(Theme.inkSecondary)
                .frame(width: lineWidth + 6, height: 1.5)
                .rotationEffect(angle)
                .position(
                    x: proxy.size.width / 2 + radius * cos(angle.radians),
                    y: proxy.size.height + radius * sin(angle.radians)
                )
        }
        .help("Typing, about \(Int(PeriodStats.typingWordsPerMinute)) wpm")
    }
}

private struct TimeSaved: View {
    let stats: PeriodStats
    let revealed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var longest: Double { max(stats.typingSeconds, stats.speakingSeconds, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Time saved")
            Text(StatsFormat.duration(stats.savedSeconds))
                .font(.display(22))
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
            VStack(alignment: .leading, spacing: 10) {
                ComparisonBar(label: "Typing", seconds: stats.typingSeconds, fraction: revealed ? stats.typingSeconds / longest : 0, fill: Theme.inkTertiary)
                ComparisonBar(label: "Speaking", seconds: stats.speakingSeconds, fraction: revealed ? stats.speakingSeconds / longest : 0, fill: Theme.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduceMotion ? nil : .reveal, value: revealed)
    }
}

private struct ComparisonBar: View {
    let label: String
    let seconds: Double
    let fraction: Double
    let fill: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label)
                    .foregroundStyle(Theme.inkSecondary)
                Spacer(minLength: 0)
                Text(seconds > 0 ? StatsFormat.duration(seconds) : "–")
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
            }
            .font(.meta)
            Capsule()
                .fill(Theme.selected)
                .frame(height: 4)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule().fill(fill).frame(width: proxy.size.width * fraction)
                    }
                }
        }
    }
}

private struct TopApps: View {
    let apps: [AppUsage]

    private var most: Int { max(apps.map(\.words).max() ?? 1, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(text: "Top apps").padding(.bottom, 4)
            ForEach(apps) { app in
                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        AppIcon(bundleID: app.bundleID, size: 18)
                        Text(app.name)
                            .font(.ui(13))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 6)
                    .frame(height: 30)
                    .background(alignment: .leading) {
                        GeometryReader { proxy in
                            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                .fill(Theme.selected)
                                .frame(width: proxy.size.width * CGFloat(app.words) / CGFloat(most))
                        }
                    }
                    Text(app.words.formatted())
                        .font(.meta)
                        .monospacedDigit()
                        .foregroundStyle(Theme.inkSecondary)
                        .contentTransition(.numericText())
                        .frame(minWidth: 36, alignment: .trailing)
                }
            }
        }
    }
}

enum StatsFormat {
    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        guard total >= 60 else { return "\(total)s" }
        let minutes = total / 60
        guard minutes >= 60 else { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}
