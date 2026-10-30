import Testing
@testable import Voz

@Suite @MainActor struct StatsModelTests {
    @Test func observesOnlyWhileStartedAndReloadsWhenReopened() async throws {
        let store = try HistoryStore()
        let model = StatsModel(store: store)
        try await store.insert(makeRecord("one two"))
        try await settleStats()
        #expect(model.stats[.all].words == 0)
        model.start()
        try await waitForStats(model) { $0[.all].words == 2 }
        try await store.insert(makeRecord("three"))
        try await waitForStats(model) { $0[.all].words == 3 }
        model.stop()
        try await store.insert(makeRecord("four five"))
        try await settleStats()
        #expect(model.stats[.all].words == 3)
        model.start()
        try await waitForStats(model) { $0[.all].words == 5 }
        model.stop()
    }

    @Test func midnightRefreshesPeriodsWithoutDatabaseWrites() async throws {
        let store = try HistoryStore()
        let clock = StatsTestClock()
        try await store.insert(makeRecord("one two", at: clock.timestamp))
        let model = StatsModel(store: store, now: clock.now)
        model.start()
        defer { model.stop() }
        try await waitForStats(model) { $0[.day].words == 2 }
        clock.nextDay()
        notifyStatsDayChanged()
        try await waitForStats(model) { $0[.day].words == 0 && $0[.all].words == 2 }
    }
}

@Suite struct PaceVerdictTests {
    @Test func comparesPaceWithHowPeopleTalk() {
        #expect(PeriodStats.paceVerdict(100) == "Calmer than most people talk")
        #expect(PeriodStats.paceVerdict(150) == "About as fast as most people talk")
        #expect(PeriodStats.paceVerdict(180) == "Faster than most people talk")
        #expect(PeriodStats.paceVerdict(PeriodStats.fastSpeakingWordsPerMinute) == "One of the fastest talkers")
    }
}
