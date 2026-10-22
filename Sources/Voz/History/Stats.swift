import Foundation
import GRDB

enum StatsPeriod: String, CaseIterable, Sendable {
    case day = "Today"
    case week = "7 days"
    case month = "30 days"
    case all = "All time"
}

struct WordBucket: Equatable, Sendable, Identifiable {
    let start: Date
    let words: Int
    var id: Date { start }
}

struct AppUsage: Hashable, Sendable {
    let bundleID: String?
    let name: String
    let words: Int
}

struct PeriodStats: Equatable, Sendable {
    var words = 0
    var speakingSeconds = 0.0
    var fixes = 0
    var wordsPerMinute: Double?
    var buckets: [WordBucket] = []
    var topApps: [AppUsage] = []

    init() {}
}

struct UsageStats: Equatable, Sendable {
    var periods: [StatsPeriod: PeriodStats] = [:]

    init() {}

    subscript(period: StatsPeriod) -> PeriodStats {
        periods[period] ?? PeriodStats()
    }
}

struct StatsRow: Decodable, FetchableRecord, Sendable {
    let createdAt: Date
    let wordCount: Int
    let audioSeconds: Double
    let fillerWordsRemoved: Int
    let appBundleID: String?
    let appName: String?
}

struct StatsAccumulator {
    private let calendar: Calendar
    private let now: Date
    private var tallies: [StatsPeriod: PeriodTally] = [:]
    private var firstDate: Date?

    init(now: Date, calendar: Calendar) {
        self.calendar = calendar
        self.now = now
    }

    mutating func add(_ row: StatsRow) {
        for period in StatsPeriod.allCases where row.createdAt >= start(of: period) {
            tallies[period, default: PeriodTally()].add(row, bucket: bucketStart(for: row.createdAt, in: period))
        }
        firstDate = min(firstDate ?? row.createdAt, row.createdAt)
    }

    func finish() -> UsageStats {
        var stats = UsageStats()
        for period in StatsPeriod.allCases {
            stats.periods[period] = tallies[period, default: PeriodTally()].finish(buckets: bucketStarts(for: period))
        }
        return stats
    }

    private func start(of period: StatsPeriod) -> Date {
        let today = calendar.startOfDay(for: now)
        switch period {
        case .day: return today
        case .week: return calendar.date(byAdding: .day, value: -6, to: today) ?? today
        case .month: return calendar.date(byAdding: .day, value: -29, to: today) ?? today
        case .all: return .distantPast
        }
    }

    private func bucketStarts(for period: StatsPeriod) -> [Date] {
        let unit = bucketUnit(of: period)
        let first = period == .all ? bucketStart(for: firstDate ?? now, in: .all) : start(of: period)
        let count = switch period {
        case .day: 24
        case .week: 7
        case .month: 30
        case .all: (calendar.dateComponents([.month], from: first, to: bucketStart(for: now, in: .all)).month ?? 0) + 1
        }
        return (0..<count).compactMap { calendar.date(byAdding: unit, value: $0, to: first) }
    }

    private func bucketStart(for date: Date, in period: StatsPeriod) -> Date {
        calendar.dateInterval(of: bucketUnit(of: period), for: date)?.start ?? date
    }

    private func bucketUnit(of period: StatsPeriod) -> Calendar.Component {
        switch period {
        case .day: .hour
        case .week, .month: .day
        case .all: .month
        }
    }
}

private struct PeriodTally {
    private static let minimumSecondsForPace = 1.0
    private static let topAppCount = 5

    private var stats = PeriodStats()
    private var wordsByBucket: [Date: Int] = [:]
    private var apps: [String: AppUsage] = [:]
    private var paceWords = 0
    private var paceSeconds = 0.0

    mutating func add(_ row: StatsRow, bucket: Date) {
        stats.words += row.wordCount
        stats.speakingSeconds += row.audioSeconds
        stats.fixes += row.fillerWordsRemoved
        wordsByBucket[bucket, default: 0] += row.wordCount
        addApp(of: row)
        guard row.audioSeconds > Self.minimumSecondsForPace else { return }
        paceWords += row.wordCount
        paceSeconds += row.audioSeconds
    }

    func finish(buckets: [Date]) -> PeriodStats {
        var result = stats
        if paceSeconds > 0 { result.wordsPerMinute = Double(paceWords) / (paceSeconds / 60) }
        result.buckets = buckets.map { WordBucket(start: $0, words: wordsByBucket[$0] ?? 0) }
        result.topApps = Array(apps.values.sorted { ($0.words, $1.name) > ($1.words, $0.name) }.prefix(Self.topAppCount))
        return result
    }

    private mutating func addApp(of row: StatsRow) {
        guard let key = row.appBundleID ?? row.appName else { return }
        let words = (apps[key]?.words ?? 0) + row.wordCount
        apps[key] = AppUsage(bundleID: row.appBundleID, name: row.appName ?? key, words: words)
    }
}
