import Charts
import Combine
import SwiftUI
import UniformTypeIdentifiers

struct InsightsPage: View {
    @ObservedObject var model: StatsModel
    let back: () -> Void
    @State private var period = StatsPeriod.week

    private var stats: PeriodStats { model.stats[period] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageBar(title: "Insights", back: back)
            if model.stats[.all].words == 0 {
                Text("Dictate something to see your stats.")
                    .font(.ui(13))
                    .foregroundStyle(Theme.inkSecondary)
            } else {
                content
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Period", selection: $period) {
                ForEach(StatsPeriod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                Text(stats.words.formatted())
                    .font(.display(32))
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
                Text(stats.words == 1 ? "word" : "words")
                    .font(.meta)
                    .foregroundStyle(Theme.inkSecondary)
            }
            WordsChart(buckets: stats.buckets, period: period)
            HStack(alignment: .top, spacing: 0) {
                StatTile(value: stats.wordsPerMinute.map { Int($0.rounded()).formatted() } ?? "–", label: "words per minute")
                StatTile(value: StatsFormat.duration(stats.speakingSeconds), label: "talking")
                StatTile(value: stats.fixes.formatted(), label: "fillers removed")
            }
            if !stats.topApps.isEmpty { TopApps(apps: stats.topApps) }
        }
        .animation(Theme.Motion.section, value: period)
    }
}

private struct StatTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.ui(17, weight: .semibold))
                .monospacedDigit()
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Top apps")
            ForEach(apps, id: \.self) { app in
                HStack(spacing: 8) {
                    AppIcon(bundleID: app.bundleID, size: 18)
                    Text(app.name)
                        .font(.ui(13))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(app.words.formatted())
                        .font(.meta)
                        .monospacedDigit()
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
        }
    }
}

private struct WordsChart: View {
    let buckets: [WordBucket]
    let period: StatsPeriod

    var body: some View {
        Chart(buckets) { bucket in
            BarMark(x: .value("Time", bucket.start, unit: unit), y: .value("Words", bucket.words), width: .ratio(0.6))
                .foregroundStyle(bucket.words > 0 ? Theme.accent : Theme.hairline)
                .cornerRadius(2)
        }
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

@MainActor
final class StatsModel: ObservableObject {
    @Published private(set) var stats = UsageStats()

    private var subscription: AnyCancellable?

    init(store: HistoryStore) {
        subscription = store.observeStats().receive(on: DispatchQueue.main).sink(
            receiveCompletion: { completion in
                if case let .failure(error) = completion {
                    Log.app.error("Stats observation failed: \(error.localizedDescription, privacy: .private)")
                }
            },
            receiveValue: { [weak self] in self?.stats = $0 }
        )
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
