import Testing
@testable import Voz

@Suite struct HistoryStoreTests {
    @Test func acceptingVocabularySuggestionAddsWordAndRemovesSuggestion() throws {
        let vocabulary = try HistoryStore().vocabulary
        try vocabulary.suggest("Voz")
        let suggestion = try #require(vocabulary.snapshot().suggestions.first)
        try vocabulary.accept(suggestion)
        try vocabulary.accept(suggestion)
        #expect(try vocabulary.words() == ["Voz"])
        #expect(try vocabulary.snapshot().suggestions.isEmpty)
    }

    @Test func searchMatchesFinalTextCaseInsensitivelyAndLiterally() throws {
        let store = try HistoryStore()
        var cleaned = makeRecord("um hello there", at: 1)
        cleaned.finalText = "Hello World."
        try store.insert(cleaned)
        try store.insert(makeRecord("Über Straße", at: 2))
        try store.insert(makeRecord("100% done", at: 3))
        #expect(try store.search("WORLD").map(\.finalText) == ["Hello World."])
        #expect(try store.search("um").isEmpty)
        #expect(try store.search("über").count == 1)
        #expect(try store.search("%").map(\.finalText) == ["100% done"])
        #expect(try store.search("_").isEmpty)
        #expect(try store.search("  ").count == 3)
    }

    @Test func recordsPersistOnDiskUntilDeleted() async throws {
        let path = makeTemporaryStorePath()
        defer { removeFile(atPath: path) }
        let first = makeRecord("one two three", at: 1)
        try await HistoryStore(path: path).insert(first)
        try await HistoryStore(path: path).insert(makeRecord("kept", at: 2))
        let saved = try #require(try HistoryStore(path: path).search("three").first)
        #expect(saved.wordCount == 3)
        #expect(saved.appBundleID == "com.apple.Notes")
        try HistoryStore(path: path).delete(id: first.id)
        #expect(try HistoryStore(path: path).search("").map(\.finalText) == ["kept"])
    }
}

@Suite struct UsageStatsTests {
    private static let day = 86_400.0
    private static let now = 1_792_670_400.0

    @Test func periodsCountWordsSpeakingTimeFixesAndPace() throws {
        let store = try HistoryStore()
        var today = makeRecord("one two three four", at: Self.now - 7_200)
        today.fillerWordsRemoved = 3
        try store.insert(today)
        try store.insert(makeRecord("five six", at: Self.now - 3 * Self.day))
        try store.insert(makeRecord("seven eight nine", at: Self.now - 20 * Self.day))
        try store.insert(makeRecord("ten eleven twelve thirteen fourteen", at: Self.now - 100 * Self.day))

        let stats = try utcStats(store, at: Self.now)

        #expect(StatsPeriod.allCases.map { stats[$0].words } == [4, 6, 9, 14])
        #expect(stats[.day].fixes == 3)
        #expect(stats[.week].speakingSeconds == 4)
        #expect(stats[.day].wordsPerMinute == 120)
        #expect(stats[.all].wordsPerMinute == 105)
    }

    @Test func extensionEntriesAreSearchableButNotCounted() throws {
        let store = try HistoryStore()
        try store.insert(makeRecord("one two", at: Self.now - 7_200))
        var meeting = makeRecord("three four five six", at: Self.now - 3_600)
        meeting.source = "voz-meeting"
        meeting.file = "/tmp/meeting.md"
        try store.insert(meeting)
        #expect(try utcStats(store, at: Self.now)[.day].words == 2)
        #expect(try store.search("four").map(\.file) == ["/tmp/meeting.md"])
    }

    @Test func topAppsRankAppsByWordsWithinEachPeriod() throws {
        let store = try HistoryStore()
        try store.insert(makeRecord("one two", at: Self.now - 7_200))
        var slack = makeRecord("three four five", at: Self.now - 3 * Self.day)
        slack.appBundleID = "com.tinyspeck.slackmacgap"
        slack.appName = "Slack"
        try store.insert(slack)
        var unknown = makeRecord("six seven eight nine", at: Self.now - 3_600)
        unknown.appBundleID = nil
        unknown.appName = nil
        try store.insert(unknown)

        let stats = try utcStats(store, at: Self.now)

        #expect(stats[.day].topApps == [AppUsage(bundleID: "com.apple.Notes", name: "Notes", words: 2)])
        #expect(stats[.week].topApps.map(\.name) == ["Slack", "Notes"])
        #expect(stats[.week].topApps.map(\.words) == [3, 2])
    }

    @Test func emptyHistoryHasNoPace() throws {
        let stats = try utcStats(HistoryStore(), at: Self.now)
        #expect(stats[.all].words == 0)
        #expect(stats[.all].wordsPerMinute == nil)
        #expect(stats.streak == 0)
    }

    @Test func streakCountsConsecutiveDaysEndingTodayAndKeepsTheLongest() throws {
        let store = try HistoryStore()
        for daysAgo in [0, 1, 2, 10, 11, 12, 13] {
            try store.insert(makeRecord("one", at: Self.now - Double(daysAgo) * Self.day))
        }
        try store.insert(makeRecord("two", at: Self.now - 3_600))

        let stats = try utcStats(store, at: Self.now)

        #expect(stats.streak == 3)
        #expect(stats.longestStreak == 4)
    }

    @Test func streakSurvivesUntilTheEndOfTodayAndBreaksAfterAMissedDay() throws {
        let store = try HistoryStore()
        try store.insert(makeRecord("one", at: Self.now - Self.day))
        try store.insert(makeRecord("two", at: Self.now - 2 * Self.day))
        #expect(try utcStats(store, at: Self.now).streak == 2)
        #expect(try utcStats(store, at: Self.now + Self.day).streak == 0)
    }

    @Test func daysCoverWholeWeeksEndingToday() throws {
        let store = try HistoryStore()
        try store.insert(makeRecord("one two three", at: Self.now - 3_600))
        try store.insert(makeRecord("four", at: Self.now - 5 * Self.day))

        let stats = try utcStats(store, at: Self.now)
        let today = Self.now - Self.now.truncatingRemainder(dividingBy: Self.day)

        #expect(stats.days.last?.start.timeIntervalSince1970 == today)
        #expect(stats.days.last?.words == 3)
        #expect(stats.days[stats.days.count - 6].words == 1)
        #expect(stats.days.map(\.words).reduce(0, +) == 4)
        #expect(stats.days.count > (UsageStats.activityWeeks - 1) * 7)
        #expect(stats.days.count <= UsageStats.activityWeeks * 7)
        #expect(utcCalendar.component(.weekday, from: stats.days[0].start) == utcCalendar.firstWeekday)
    }

    @Test func timeSavedComparesSpeakingWithTypingAtFortyWordsPerMinute() {
        var stats = PeriodStats()
        stats.words = 400
        stats.speakingSeconds = 120
        #expect(stats.typingSeconds == 600)
        #expect(stats.savedSeconds == 480)
        stats.speakingSeconds = 900
        #expect(stats.savedSeconds == 0)
    }
}
