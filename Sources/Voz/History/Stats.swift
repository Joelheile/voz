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
    static let averageSpeakingWordsPerMinute = 150.0
    static let fastSpeakingWordsPerMinute = 190.0

    static func paceVerdict(_ wordsPerMinute: Double) -> String {
        switch wordsPerMinute {
        case ..<120: "Calmer than most people talk"
        case ..<170: "About as fast as most people talk"
        case ..<fastSpeakingWordsPerMinute: "Faster than most people talk"
        default: "One of the fastest talkers"
        }
    }

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

struct Milestone: Equatable {
    static let maxShows = 3

    enum Kind: String, CaseIterable {
        case words
        case streak
        case hoursSaved

        var thresholds: [Int] {
            switch self {
            case .words: [1_000, 2_000, 5_000, 10_000, 25_000, 50_000, 100_000]
            case .streak: [7, 30, 100, 365]
            case .hoursSaved: [1, 10, 100]
            }
        }

        func amount(in stats: UsageStats) -> Int {
            switch self {
            case .words: stats[.all].words
            case .streak: stats.streak
            case .hoursSaved: Int(stats[.all].savedSeconds / 3600)
            }
        }
    }

    let kind: Kind
    let value: Int

    var title: String {
        switch kind {
        case .words: "\(value.formatted()) words"
        case .streak: "\(value) day streak"
        case .hoursSaved: value == 1 ? "1 hour saved" : "\(value.formatted()) hours saved"
        }
    }

    static func reached(in stats: UsageStats) -> [Milestone] {
        Kind.allCases.compactMap { kind in
            let amount = kind.amount(in: stats)
            return kind.thresholds.last { $0 <= amount }.map { Milestone(kind: kind, value: $0) }
        }
    }

    static func unseen(in stats: UsageStats, seen: [String: Int]) -> Milestone? {
        reached(in: stats).first { $0.value > seen[$0.kind.rawValue, default: 0] }
    }

    static func markingSeen(in stats: UsageStats, seen: [String: Int]) -> [String: Int] {
        reached(in: stats).reduce(into: seen) { $0[$1.kind.rawValue] = max($0[$1.kind.rawValue, default: 0], $1.value) }
    }
}
