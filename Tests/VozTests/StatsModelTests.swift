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

@Suite struct MilestoneTests {
    private func usage(words: Int, streak: Int = 0) -> UsageStats {
        var stats = UsageStats()
        var all = PeriodStats()
        all.words = words
        stats.periods[.all] = all
        stats.streak = streak
        return stats
    }

    @Test func showsTheHighestReachedMilestoneOnce() {
        let stats = usage(words: 5_400, streak: 8)
        #expect(Milestone.unseen(in: stats, seen: [:]) == Milestone(kind: .words, value: 5_000))
        let seen = Milestone.markingSeen(in: stats, seen: [:])
        #expect(Milestone.unseen(in: stats, seen: seen) == nil)
        #expect(Milestone.unseen(in: usage(words: 10_000, streak: 8), seen: seen) == Milestone(kind: .words, value: 10_000))
    }

    @Test func showsNothingBeforeTheFirstMilestone() {
        #expect(Milestone.unseen(in: usage(words: 999, streak: 6), seen: [:]) == nil)
    }

    @Test func aBrokenStreakDoesNotLowerWhatWasSeen() {
        let seen = Milestone.markingSeen(in: usage(words: 0, streak: 30), seen: [:])
        #expect(Milestone.markingSeen(in: usage(words: 0, streak: 7), seen: seen)["streak"] == 30)
        #expect(Milestone.unseen(in: usage(words: 0, streak: 7), seen: seen) == nil)
    }
}
