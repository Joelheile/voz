import Charts
import SwiftUI
import VozCore

struct InsightsView: View {
    @ObservedObject var model: StatsModel

    private var stats: UsageStats { model.stats }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.item), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.section) {
            PageHeader(title: "Insights", subtitle: "How much you have dictated, and how much typing it saved.")
            HStack(spacing: Theme.Spacing.item) {
                FeatureStat(label: "This week", value: stats.wordsThisWeek, unit: "words")
                FeatureStat(label: "Time saved", text: StatsFormat.minutes(stats.minutesSaved), unit: "vs. typing")
            }
            LazyVGrid(columns: columns, spacing: Theme.Spacing.item) {
                SmallStat(label: "Today", value: stats.wordsToday.formatted(), unit: "words")
                SmallStat(label: "All time", value: stats.wordsTotal.formatted(), unit: "words")
                SmallStat(label: "Pace", value: Int((stats.averageWordsPerMinute ?? 0).rounded()).formatted(), unit: "wpm")
                SmallStat(label: "Current streak", value: stats.currentStreak.formatted(), unit: stats.currentStreak == 1 ? "day" : "days")
                SmallStat(label: "Longest streak", value: stats.longestStreak.formatted(), unit: stats.longestStreak == 1 ? "day" : "days")
                SmallStat(label: "Filler words removed", value: stats.fillerWordsRemoved.formatted(), unit: "")
            }
            DailyChart(days: stats.dailyWords)
            TopApps(apps: stats.topApps)
        }
    }
}

private struct FeatureStat: View {
    let label: String
    var value: Int?
    var text: String?
    let unit: String

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel(text: label)
                if let value {
                    StatNumber(value: value, unit: unit, size: 64)
                } else if let text {
                    StatText(value: text, unit: unit, size: 64)
                }
            }
        }
    }
}

private struct SmallStat: View {
    let label: String
    let value: String
    let unit: String

    var body: some View {
        Card(padding: 20) {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: label)
                StatText(value: value, unit: unit, size: 34)
            }
        }
    }
}

private struct DailyChart: View {
    let days: [DailyWords]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 20) {
                SectionTitle(text: "Last 30 days")
                Chart(days) { day in
                    BarMark(x: .value("Day", day.day, unit: .day), y: .value("Words", day.words))
                        .foregroundStyle(Theme.accent)
                        .cornerRadius(3)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .font(.meta)
                            .foregroundStyle(Theme.inkTertiary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine().foregroundStyle(Theme.hairline)
                        AxisValueLabel().font(.meta).foregroundStyle(Theme.inkTertiary)
                    }
                }
                .frame(height: 200)
            }
        }
    }
}

private struct TopApps: View {
    let apps: [AppUsage]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 18) {
                SectionTitle(text: "Top apps")
                if apps.isEmpty {
                    Text("Apps you dictate into show up here.")
                        .font(.meta)
                        .foregroundStyle(Theme.inkSecondary)
                }
                ForEach(apps, id: \.appName) { app in
                    HStack(spacing: 16) {
                        Text(app.appName)
                            .font(.rowTitle)
                            .foregroundStyle(Theme.ink)
                            .frame(width: 140, alignment: .leading)
                            .lineLimit(1)
                        UsageBar(fraction: Double(app.words) / Double(max(apps.first?.words ?? 1, 1)))
                        Text(app.words.formatted())
                            .font(.meta)
                            .monospacedDigit()
                            .foregroundStyle(Theme.inkSecondary)
                            .frame(width: 56, alignment: .trailing)
                    }
                }
            }
        }
    }
}

private struct UsageBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.canvas)
                Capsule().fill(Theme.accent).frame(width: max(8, proxy.size.width * fraction))
            }
        }
        .frame(height: 8)
    }
}
