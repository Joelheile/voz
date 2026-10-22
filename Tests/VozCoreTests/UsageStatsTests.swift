import Testing
import VozCore

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

    @Test func bucketsCoverThePeriodAndPlaceWordsInTheirSlot() throws {
        let store = try HistoryStore()
        try store.insert(makeRecord("one two three four", at: Self.now - 7_200))
        try store.insert(makeRecord("five six", at: Self.now - 3 * Self.day))
        try store.insert(makeRecord("ten eleven", at: Self.now - 100 * Self.day))

        let stats = try utcStats(store, at: Self.now)

        #expect(stats[.day].buckets.count == 24)
        #expect(stats[.day].buckets[10].words == 4)
        #expect(stats[.week].buckets.map(\.words) == [0, 0, 0, 2, 0, 0, 4])
        #expect(stats[.month].buckets.count == 30)
        #expect(stats[.all].buckets.map(\.words) == [2, 0, 0, 6])
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
        #expect(stats[.all].buckets.count == 1)
    }
}
