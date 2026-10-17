import Testing
@testable import VozCore

@Suite struct StatsTests {
    @Test func emptyHistoryHasZeroStats() {
        let stats = StatsFixture.stats([])
        #expect(stats.wordsTotal == 0)
        #expect(stats.averageWordsPerMinute == nil)
        #expect(stats.minutesSaved == 0)
        #expect(stats.currentStreak == 0)
        #expect(stats.longestStreak == 0)
        #expect(stats.topApps.isEmpty)
    }

    @Test func countsWordsForTodayWeekAndTotal() {
        let stats = StatsFixture.stats([
            DictationEntry(daysAgo: 0, words: 10),
            DictationEntry(daysAgo: 0, hour: 1, words: 5),
            DictationEntry(daysAgo: 2, words: 20),
            DictationEntry(daysAgo: 3, words: 40),
            DictationEntry(daysAgo: 30, words: 100),
        ])
        #expect(stats.wordsToday == 15)
        #expect(stats.wordsThisWeek == 35)
        #expect(stats.wordsTotal == 175)
    }

    @Test func averagePaceIgnoresRecordingsOfOneSecondOrLess() {
        let stats = StatsFixture.stats([
            DictationEntry(words: 100, seconds: 60),
            DictationEntry(words: 50, seconds: 1),
            DictationEntry(words: 20, seconds: 0.5),
        ])
        #expect(stats.averageWordsPerMinute == 100)
    }

    @Test func timeSavedComparesTypingAtFortyWordsPerMinute() {
        let stats = StatsFixture.stats([DictationEntry(words: 400, seconds: 300)])
        #expect(stats.minutesSaved == 5)
    }

    @Test func timeSavedNeverGoesBelowZero() {
        let stats = StatsFixture.stats([DictationEntry(words: 10, seconds: 600)])
        #expect(stats.minutesSaved == 0)
    }

    @Test func streaksCountConsecutiveCalendarDays() {
        let stats = StatsFixture.stats([0, 1, 2, 4, 5, 6, 7].map { DictationEntry(daysAgo: $0) })
        #expect(stats.currentStreak == 3)
        #expect(stats.longestStreak == 4)
    }

    @Test func streakSurvivesUntilEndOfToday() {
        let stats = StatsFixture.stats([DictationEntry(daysAgo: 1), DictationEntry(daysAgo: 2)])
        #expect(stats.currentStreak == 2)
    }

    @Test func streakBreaksAfterAMissedDay() {
        let stats = StatsFixture.stats([DictationEntry(daysAgo: 2), DictationEntry(daysAgo: 3)])
        #expect(stats.currentStreak == 0)
        #expect(stats.longestStreak == 2)
    }

    @Test func lateNightAndEarlyMorningAreSeparateDays() {
        let stats = StatsFixture.stats([DictationEntry(daysAgo: 1, hour: 23), DictationEntry(daysAgo: 0, hour: 0)])
        #expect(stats.currentStreak == 2)
    }

    @Test func topAppsAreSortedByWordsAndLimitedToFive() {
        let apps = ["A": 10, "B": 70, "C": 30, "D": 20, "E": 60, "F": 50, "G": 40]
        var entries = apps.map { DictationEntry(words: $0.value, app: $0.key) }
        entries.append(DictationEntry(words: 999, app: nil))
        let stats = StatsFixture.stats(entries)
        #expect(stats.topApps.map(\.appName) == ["B", "E", "F", "G", "C"])
        #expect(stats.topApps.first?.words == 70)
    }

    @Test func sumsFillerWordsRemoved() {
        let stats = StatsFixture.stats([DictationEntry(fillers: 3), DictationEntry(daysAgo: 5, fillers: 4)])
        #expect(stats.fillerWordsRemoved == 7)
    }

    @Test func dailySeriesCoversThirtyDaysEndingToday() {
        let stats = StatsFixture.stats([
            DictationEntry(daysAgo: 0, words: 7),
            DictationEntry(daysAgo: 29, words: 3),
            DictationEntry(daysAgo: 30, words: 99),
        ])
        #expect(stats.dailyWords.count == 30)
        #expect(stats.dailyWords.last?.words == 7)
        #expect(stats.dailyWords.first?.words == 3)
        #expect(stats.dailyWords.dropFirst().dropLast().allSatisfy { $0.words == 0 })
    }

    @Test func storeAggregatesWithoutLoadingTexts() throws {
        let store = try HistoryStore()
        let stats = try StatsFixture.stats(in: store, entries: [
            DictationEntry(daysAgo: 0, words: 12, seconds: 6, fillers: 2),
            DictationEntry(daysAgo: 1, words: 8, seconds: 4, app: "Mail"),
        ])
        #expect(stats.wordsTotal == 20)
        #expect(stats.currentStreak == 2)
        #expect(stats.fillerWordsRemoved == 2)
        #expect(stats.topApps.map(\.appName) == ["Notes", "Mail"])
    }
}
