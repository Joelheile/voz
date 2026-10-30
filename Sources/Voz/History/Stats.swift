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

struct AppUsage: Hashable, Sendable, Identifiable {
    let bundleID: String?
    let name: String
    let words: Int
    var id: String { bundleID ?? name }
}

struct PeriodStats: Equatable, Sendable {
    static let typingWordsPerMinute = 40.0

    var words = 0
    var speakingSeconds = 0.0
    var fixes = 0
    var wordsPerMinute: Double?
    var topApps: [AppUsage] = []

    init() {}

    var typingSeconds: Double { Double(words) / Self.typingWordsPerMinute * 60 }
    var savedSeconds: Double { max(typingSeconds - speakingSeconds, 0) }
}

struct UsageStats: Equatable, Sendable {
    static let activityWeeks = 25

    var periods: [StatsPeriod: PeriodStats] = [:]
    var days: [WordBucket] = []
    var streak = 0
    var longestStreak = 0

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
    private var wordsByDay: [Date: Int] = [:]

    init(now: Date, calendar: Calendar) {
        self.calendar = calendar
        self.now = now
    }

    mutating func add(_ row: StatsRow) {
        for period in StatsPeriod.allCases where row.createdAt >= start(of: period) {
            tallies[period, default: PeriodTally()].add(row)
        }
        wordsByDay[calendar.startOfDay(for: row.createdAt), default: 0] += row.wordCount
    }

    func finish() -> UsageStats {
        var stats = UsageStats()
        for period in StatsPeriod.allCases {
            stats.periods[period] = tallies[period, default: PeriodTally()].finish()
        }
        stats.days = activityDays().map { WordBucket(start: $0, words: wordsByDay[$0] ?? 0) }
        stats.streak = currentStreak()
        stats.longestStreak = longestStreak()
        return stats
    }

    private func activityDays() -> [Date] {
        let today = calendar.startOfDay(for: now)
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        guard let first = calendar.date(byAdding: .weekOfYear, value: 1 - UsageStats.activityWeeks, to: thisWeek) else { return [] }
        let count = (calendar.dateComponents([.day], from: first, to: today).day ?? 0) + 1
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
    }

    private func currentStreak() -> Int {
        let today = calendar.startOfDay(for: now)
        guard var day = wordsByDay[today] == nil ? calendar.date(byAdding: .day, value: -1, to: today) : today else { return 0 }
        var count = 0
        while wordsByDay[day] != nil, let previous = calendar.date(byAdding: .day, value: -1, to: day) {
            count += 1
            day = previous
        }
        return count
    }

    private func longestStreak() -> Int {
        var longest = 0
        var run = 0
        var previous: Date?
        for day in wordsByDay.keys.sorted() {
            let followsPrevious = previous.flatMap { calendar.date(byAdding: .day, value: 1, to: $0) } == day
            run = followsPrevious ? run + 1 : 1
            longest = max(longest, run)
            previous = day
        }
        return longest
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
}

private struct PeriodTally {
    private static let minimumSecondsForPace = 1.0
    private static let topAppCount = 5

    private var stats = PeriodStats()
    private var apps: [String: AppUsage] = [:]
    private var paceWords = 0
    private var paceSeconds = 0.0

    mutating func add(_ row: StatsRow) {
        stats.words += row.wordCount
        stats.speakingSeconds += row.audioSeconds
        stats.fixes += row.fillerWordsRemoved
        addApp(of: row)
        guard row.audioSeconds > Self.minimumSecondsForPace else { return }
        paceWords += row.wordCount
        paceSeconds += row.audioSeconds
    }

    func finish() -> PeriodStats {
        var result = stats
        if paceSeconds > 0 { result.wordsPerMinute = Double(paceWords) / (paceSeconds / 60) }
        result.topApps = Array(apps.values.sorted { ($0.words, $1.name) > ($1.words, $0.name) }.prefix(Self.topAppCount))
        return result
    }

    private mutating func addApp(of row: StatsRow) {
        guard let key = row.appBundleID ?? row.appName else { return }
        let words = (apps[key]?.words ?? 0) + row.wordCount
        apps[key] = AppUsage(bundleID: row.appBundleID, name: row.appName ?? key, words: words)
    }
}
