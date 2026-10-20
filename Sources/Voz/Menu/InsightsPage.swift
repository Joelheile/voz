import Charts
import SwiftUI
import VozCore

struct InsightsPage: View {
    @ObservedObject var model: StatsModel
    let back: () -> Void

    private var stats: UsageStats { model.stats }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageBar(title: "Insights", back: back)
            CappedScrollView(maxHeight: 540) {
                VStack(alignment: .leading, spacing: 20) {
                    summary
                    DailyChart(days: stats.dailyWords)
                    TopApps(apps: Array(stats.topApps.prefix(5)))
                    Text("Time saved assumes you type 40 words per minute.")
                        .font(.ui(11.5))
                        .foregroundStyle(Theme.inkTertiary)
                }
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(stats.wordsThisWeek.formatted()) words this week")
                .font(.ui(24, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
            Text(details.joined(separator: " "))
                .font(.ui(13))
                .lineSpacing(3)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var details: [String] {
        var sentences = ["\(stats.wordsToday.formatted()) today, \(stats.wordsTotal.formatted()) in total, about \(StatsFormat.minutes(stats.minutesSaved)) of typing saved."]
        if let pace = stats.averageWordsPerMinute {
            sentences.append("You speak at \(Int(pace.rounded())) words per minute.")
        }
        if stats.currentStreak > 0 {
            sentences.append("You are on a \(stats.currentStreak)-day streak. Your longest is \(StatsFormat.days(stats.longestStreak)).")
        }
        if stats.fillerWordsRemoved > 0 {
            sentences.append("Voz removed \(stats.fillerWordsRemoved.formatted()) filler words.")
        }
        return sentences
    }
}

private struct DailyChart: View {
    let days: [DailyWords]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Last 30 days")
            Chart(days) { day in
                BarMark(x: .value("Day", day.day, unit: .day), y: .value("Words", day.words))
                    .foregroundStyle(Theme.accent)
                    .cornerRadius(2)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .font(.ui(10))
                        .foregroundStyle(Theme.inkTertiary)
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 90)
        }
    }
}

private struct TopApps: View {
    let apps: [AppUsage]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Top apps")
            if apps.isEmpty {
                Text("Apps you dictate into appear here.")
                    .font(.meta)
                    .foregroundStyle(Theme.inkSecondary)
            }
            ForEach(apps, id: \.appName) { app in
                HStack(spacing: 10) {
                    Text(app.appName)
                        .font(.ui(12.5, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 90, alignment: .leading)
                        .lineLimit(1)
                    UsageBar(fraction: Double(app.words) / Double(max(apps.first?.words ?? 1, 1)))
                    Text(app.words.formatted())
                        .font(.ui(12))
                        .monospacedDigit()
                        .foregroundStyle(Theme.inkSecondary)
                        .frame(width: 44, alignment: .trailing)
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
                Capsule().fill(Theme.hairline)
                Capsule().fill(Theme.accent).frame(width: max(6, proxy.size.width * fraction))
            }
        }
        .frame(height: 6)
    }
}
