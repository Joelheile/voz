import Foundation

public struct StatsAccumulator {
    private static let minimumSecondsForPace = 1.0

    private let calendar: Calendar
    private let today: Date
    private let week: DateInterval
    private let seriesStart: Date
    private var wordsByDay: [Date: Int] = [:]
    private var wordsByApp: [String: Int] = [:]
    private var stats = UsageStats()
    private var allAudioSeconds = 0.0
    private var paceWords = 0
    private var paceSeconds = 0.0

    public init(now: Date, calendar: Calendar) {
        self.calendar = calendar
        today = calendar.startOfDay(for: now)
        week = calendar.dateInterval(of: .weekOfYear, for: now) ?? DateInterval(start: today, duration: 0)
        seriesStart = calendar.date(byAdding: .day, value: 1 - UsageStats.seriesDays, to: today) ?? today
    }

    public mutating func add(_ row: StatsRow) {
        let day = calendar.startOfDay(for: row.createdAt)
        wordsByDay[day, default: 0] += row.wordCount
        stats.wordsTotal += row.wordCount
        stats.fillerWordsRemoved += row.fillerWordsRemoved
        allAudioSeconds += row.audioSeconds
        if day == today { stats.wordsToday += row.wordCount }
        if week.contains(row.createdAt) { stats.wordsThisWeek += row.wordCount }
        if row.audioSeconds > Self.minimumSecondsForPace {
            paceWords += row.wordCount
            paceSeconds += row.audioSeconds
        }
        if let appName = row.appName { wordsByApp[appName, default: 0] += row.wordCount }
    }

    public func finish() -> UsageStats {
        var result = stats
        if paceSeconds > 0 { result.averageWordsPerMinute = Double(paceWords) / (paceSeconds / 60) }
        let typingMinutes = Double(stats.wordsTotal) / UsageStats.typingWordsPerMinute
        result.minutesSaved = max(0, typingMinutes - allAudioSeconds / 60)
        result.topApps = wordsByApp
            .map { AppUsage(appName: $0.key, words: $0.value) }
            .sorted { ($0.words, $1.appName) > ($1.words, $0.appName) }
            .prefix(UsageStats.topAppCount)
            .map { $0 }
        result.currentStreak = currentStreak()
        result.longestStreak = longestStreak()
        result.dailyWords = (0..<UsageStats.seriesDays).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: seriesStart).map { DailyWords(day: $0, words: wordsByDay[$0] ?? 0) }
        }
        return result
    }

    private func currentStreak() -> Int {
        guard var day = [today, calendar.date(byAdding: .day, value: -1, to: today)].compactMap({ $0 }).first(where: wordsByDay.keys.contains) else {
            return 0
        }
        var streak = 0
        while wordsByDay[day] != nil {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    private func longestStreak() -> Int {
        var longest = 0
        var run = 0
        var previous: Date?
        for day in wordsByDay.keys.sorted() {
            if let previous, calendar.date(byAdding: .day, value: 1, to: previous) == day {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
            previous = day
        }
        return longest
    }
}
