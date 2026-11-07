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

    @Test func searchMatchesEveryWordInAnyOrderAcrossTextAndApp() throws {
        let store = try HistoryStore()
        try store.insert(makeRecord("Send the invoice to Anna", at: 1))
        var slack = makeRecord("Standup moved to Friday", at: 2)
        slack.appName = "Slack"
        try store.insert(slack)
        #expect(try store.search("anna invoice").map(\.finalText) == ["Send the invoice to Anna"])
        #expect(try store.search("slack friday").map(\.finalText) == ["Standup moved to Friday"])
        #expect(try store.search("voice").map(\.finalText) == ["Send the invoice to Anna"])
    }

    @Test func searchFallsBackToCloseMatchesForTypos() throws {
        let store = try HistoryStore()
        try store.insert(makeRecord("Book the quarterly planning meeting", at: 1))
        try store.insert(makeRecord("Buy oat milk", at: 2))
        #expect(try store.search("quartrly planing").map(\.finalText) == ["Book the quarterly planning meeting"])
        #expect(try store.search("zebra crossing").isEmpty)
    }

    @Test func searchIndexForgetsDeletedTranscripts() throws {
        let store = try HistoryStore()
        let record = makeRecord("Renew the passport", at: 1)
        try store.insert(record)
        #expect(try store.recent(matching: "passport", limit: 5).count == 1)
        try store.delete(id: record.id)
        #expect(try store.search("passport").isEmpty)
    }

    @Test func todayAndYesterdayFilterByDay() {
        let midnight = 1_792_627_200.0
        let noon = midnight + 12 * 3_600
        #expect(utcSearchDays("today", at: noon) == [midnight, midnight + 86_400])
        #expect(utcSearchDays("invoice yesterday", at: noon) == [midnight - 86_400, midnight])
        #expect(utcSearchDays("invoice", at: noon) == nil)
    }

    @Test func extensionEntriesKeepTheirPartsToCopy() throws {
        let path = makeTemporaryStorePath()
        defer { removeFile(atPath: path) }
        let parts = [HistoryCopy(name: "Notes", text: "ship fri"), HistoryCopy(name: "Transcript", text: "Speaker 1: Ship it")]
        try HistoryStore(path: path).insert(TranscriptRecord(ExtensionHistoryEntry(extension: "voz-meeting", text: "Summary", seconds: 60, file: nil, copies: parts)))
        try HistoryStore(path: path).insert(makeRecord("plain", at: 2))
        let saved = try HistoryStore(path: path).search("")
        #expect(saved.first { $0.source == "voz-meeting" }?.copies == parts)
        #expect(saved.first { $0.source == nil }?.copies == nil)
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
        #expect(StatsPeriod.allCases.map { stats[$0].dictations } == [1, 2, 3, 4])
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

@Suite struct TranscriptDayTests {
    private let day = 86_400.0

    @Test func steppingSkipsDaysWithoutTranscripts() {
        let days = TranscriptDays([epoch(0), epoch(3 * day), epoch(5 * day)])
        #expect(days.earlier(than: epoch(5 * day)) == epoch(3 * day))
        #expect(days.earlier(than: epoch(0)) == nil)
        #expect(days.later(than: epoch(0)) == epoch(3 * day))
        #expect(days.later(than: epoch(5 * day)) == nil)
    }

    @Test func storeListsEachDayOnceAtItsStart() throws {
        let store = try HistoryStore()
        try store.insert(makeRecord("morning", at: 3_600))
        try store.insert(makeRecord("evening", at: 72_000))
        try store.insert(makeRecord("much later", at: 4 * day + 60))
        let days = try store.transcriptDays(calendar: utcCalendar)
        #expect(days == TranscriptDays([epoch(0), epoch(4 * day)]))
    }

    @Test func aDayListsAllItsTranscriptsNewestFirstAndNoOthers() throws {
        let store = try HistoryStore()
        try store.insert(makeRecord("other day", at: 60))
        let count = HistoryStore.searchLimit + 2
        for minute in 0..<count {
            try store.insert(makeRecord("minute \(minute)", at: day + Double(minute) * 60))
        }
        let shown = try store.records(on: utcDay(at: day))
        #expect(shown.count == count, "a day is never cut off by a limit")
        #expect(shown.first?.finalText == "minute \(count - 1)")
        #expect(!shown.contains { $0.finalText == "other day" })
    }

    @Test func aMonthStartsOnTheUsersFirstWeekdayAndAlwaysFillsSixWeeks() {
        // 1 November 2026 is a Sunday
        #expect(utcMonthCells(at: 1_793_577_600, firstWeekday: 1).prefix(2) == [1, 2])
        #expect(utcMonthCells(at: 1_793_577_600, firstWeekday: 2).prefix(7) == [nil, nil, nil, nil, nil, nil, 1])
        #expect(utcMonthCells(at: 1_793_577_600, firstWeekday: 2).count == 42)
        #expect(utcMonthCells(at: 1_793_577_600, firstWeekday: 2).compactMap { $0 }.last == 30)
    }
}

@MainActor @Suite struct HistoryModelDayTests {
    private static let day = 86_400.0
    private let older = 10 * day + 43_200
    private let newer = 13 * day + 43_200

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<300 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func model(store: HistoryStore) async throws -> HistoryModel {
        try await store.insert(makeRecord("older", at: older))
        try await store.insert(makeRecord("newer", at: newer))
        try await store.insert(makeRecord("today", at: nowSeconds()))
        let model = HistoryModel(store: store)
        await waitUntil { model.days.oldest != nil && model.records.count == 1 }
        return model
    }

    @Test func opensOnTodayWithOnlyTodaysTranscripts() async throws {
        let model = try await model(store: HistoryStore())
        #expect(model.day == localToday())
        #expect(model.records.map(\.finalText) == ["today"])
    }

    @Test func arrowsStepThroughDaysWithTranscriptsAndStopAtBothEnds() async throws {
        let model = try await model(store: HistoryStore())
        #expect(model.showLaterDay() == false, "there is nothing after today")
        #expect(model.showEarlierDay())
        #expect(model.day == localDayStart(at: newer))
        #expect(model.showEarlierDay())
        #expect(model.day == localDayStart(at: older))
        #expect(model.showEarlierDay() == false)
        #expect(model.day == localDayStart(at: older), "the oldest day stays picked")
        #expect(model.showLaterDay())
        #expect(model.showLaterDay())
        #expect(model.day == localToday())
    }

    @Test func aPickedDayListsItsTranscriptsAndClosesTheCalendar() async throws {
        let model = try await model(store: HistoryStore())
        model.showsCalendar = true
        model.pick(localDayStart(at: older))
        await waitUntil { model.records.map(\.finalText) == ["older"] }
        #expect(model.records.map(\.finalText) == ["older"])
        #expect(model.listedDay == localDayStart(at: older))
        #expect(model.showsCalendar == false)
    }

    @Test func searchLooksThroughEveryDay() async throws {
        let model = try await model(store: HistoryStore())
        model.query = "older"
        await waitUntil { model.records.map(\.finalText) == ["older"] }
        #expect(model.records.map(\.finalText) == ["older"])
        #expect(model.listedDay == nil)
    }

    @Test func escapeClosesTheCalendarThenClearsTheSearch() async throws {
        let model = try await model(store: HistoryStore())
        model.query = "older"
        model.showsCalendar = true
        #expect(model.dismissFilter())
        #expect(model.showsCalendar == false && model.query == "older")
        #expect(model.dismissFilter())
        #expect(model.query.isEmpty)
        #expect(model.dismissFilter() == false, "with nothing left, Escape closes the panel as before")
    }

    @Test func resetGoesBackToToday() async throws {
        let model = try await model(store: HistoryStore())
        model.pick(localDayStart(at: older))
        model.reset()
        #expect(model.day == localToday())
    }

    @Test func deletingAPastDaysLastTranscriptGoesBackToToday() async throws {
        let model = try await model(store: HistoryStore())
        model.pick(localDayStart(at: older))
        await waitUntil { model.records.map(\.finalText) == ["older"] }
        model.delete(try #require(model.records.first))
        await waitUntil { model.day == localToday() }
        #expect(model.day == localToday())
    }
}
