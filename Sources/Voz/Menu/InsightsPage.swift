import Charts
import SwiftUI
import UniformTypeIdentifiers

struct InsightsPage: View {
    @ObservedObject var model: StatsModel
    @ObservedObject var settings: AppSettings
    let back: () -> Void
    @State private var period = StatsPeriod.week
    @State private var hovered: WordBucket?

    private var stats: PeriodStats { model.stats[period] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageBar(title: "Insights", back: back)
            if model.stats[.all].words == 0 {
                Text("Dictate something to see your stats.")
                    .font(.ui(13))
                    .foregroundStyle(Theme.inkSecondary)
            } else {
                if !settings.starPromptDismissed, model.stats[.all].words >= StarPromptCard.threshold {
                    StarPromptCard(words: model.stats[.all].words) {
                        withAnimation(Theme.Motion.section) { settings.starPromptDismissed = true }
                    }
                    .transition(.opacity)
                }
                content
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            TabBar(tabs: StatsPeriod.allCases, selection: $period)
            VStack(alignment: .leading, spacing: 2) {
                Text((hovered?.words ?? stats.words).formatted())
                    .font(.display(32))
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
                Text(caption)
                    .font(.meta)
                    .foregroundStyle(Theme.inkSecondary)
                    .contentTransition(.interpolate)
            }
            .animation(.snappy(duration: 0.18), value: hovered)
            WordsChart(buckets: stats.buckets, period: period, hovered: $hovered)
            HStack(alignment: .top, spacing: 0) {
                StatTile(value: stats.wordsPerMinute.map { Int($0.rounded()).formatted() } ?? "–", label: "words per minute")
                StatTile(value: StatsFormat.duration(stats.speakingSeconds), label: "talking")
                StatTile(value: stats.fixes.formatted(), label: "fillers removed")
            }
            if !stats.topApps.isEmpty { TopApps(apps: stats.topApps) }
        }
        .animation(Theme.Motion.section, value: period)
        .onChange(of: period) { hovered = nil }
    }

    private var caption: String {
        let words = hovered?.words ?? stats.words
        let unit = words == 1 ? "word" : "words"
        guard let hovered else { return unit }
        return "\(unit), \(hovered.start.formatted(period.hoverFormat))"
    }
}

private extension StatsPeriod {
    var hoverFormat: Date.FormatStyle {
        switch self {
        case .day: .dateTime.hour()
        case .week: .dateTime.weekday(.wide)
        case .month: .dateTime.weekday(.abbreviated).month(.abbreviated).day()
        case .all: .dateTime.month(.wide).year()
        }
    }
}

private struct StatTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.display(20))
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
            Text(label)
                .font(.meta)
                .foregroundStyle(Theme.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TopApps: View {
    let apps: [AppUsage]

    private var most: Int { max(apps.map(\.words).max() ?? 1, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(text: "Top apps").padding(.bottom, 4)
            ForEach(apps, id: \.self) { app in
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

private struct WordsChart: View {
    let buckets: [WordBucket]
    let period: StatsPeriod
    @Binding var hovered: WordBucket?
    @State private var selection: Date?

    var body: some View {
        Chart {
            ForEach(buckets) { bucket in
                BarMark(x: .value("Time", bucket.start, unit: unit), y: .value("Words", bucket.words), width: .ratio(0.6))
                    .foregroundStyle(Theme.accent.opacity(hovered == nil || hovered == bucket ? 1 : 0.3))
                    .cornerRadius(3)
            }
            RuleMark(y: .value("None", 0))
                .foregroundStyle(Theme.hairline)
                .lineStyle(StrokeStyle(lineWidth: 1))
        }
        .chartXSelection(value: $selection)
        .onChange(of: selection) { hovered = selection.flatMap(bucket(at:)) }
        .animation(Theme.Motion.hover, value: hovered)
        .chartXAxis {
            AxisMarks(values: axisValues) { _ in
                AxisValueLabel(format: axisFormat)
                    .font(.ui(11))
                    .foregroundStyle(Theme.inkTertiary)
            }
        }
        .chartYAxis(.hidden)
        .frame(height: 96)
    }

    private func bucket(at date: Date) -> WordBucket? {
        buckets.last { $0.start <= date }
    }

    private var unit: Calendar.Component {
        switch period {
        case .day: .hour
        case .week, .month: .day
        case .all: .month
        }
    }

    private var axisValues: AxisMarkValues {
        switch period {
        case .day: .stride(by: .hour, count: 6)
        case .week: .stride(by: .day)
        case .month: .stride(by: .day, count: 7)
        case .all: .automatic(desiredCount: 4)
        }
    }

    private var axisFormat: Date.FormatStyle {
        switch period {
        case .day: .dateTime.hour()
        case .week: .dateTime.weekday(.abbreviated)
        case .month: .dateTime.month(.abbreviated).day()
        case .all: .dateTime.month(.abbreviated)
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
