import Testing
@testable import Voz

@Suite struct DraftStoreTests {
    @Test func aThreadIsOnePerAppAndTitleAndRemembersWhenItWasSeen() throws {
        let drafts = try HistoryStore().drafts
        let first = try drafts.thread(app: "com.tinyspeck.slackmacgap", title: "Anna", at: epoch(1))
        let again = try drafts.thread(app: "com.tinyspeck.slackmacgap", title: "Anna", at: epoch(5))
        let elsewhere = try drafts.thread(app: "com.apple.MobileSMS", title: "Anna", at: epoch(6))
        #expect(again.id == first.id)
        #expect(again.createdAt == epoch(1))
        #expect(again.seenAt == epoch(5))
        #expect(elsewhere.id != first.id)
        #expect(try drafts.thread(app: "com.apple.MobileSMS", window: "(3) Messages", appName: "Messages") == nil)
        #expect(try drafts.thread(app: nil, window: "Anna", appName: nil) == nil)
    }

    @Test func deletingADictationErasesItsWordsFromTheDraftThatReplacedIt() throws {
        let store = try HistoryStore()
        let dictated = makeRecord("my private words", at: 1)
        try store.insert(dictated)
        var replacement = makeDraft("A reply", at: 2, input: "my private words")
        replacement.transcriptID = dictated.id
        try store.drafts.insert(replacement)
        try store.drafts.insert(makeDraft("Unrelated", at: 3, input: "someone else's words"))

        try store.delete(id: dictated.id)

        let drafts = try store.drafts.recent(limit: 10).map(\.draft)
        #expect(drafts.map(\.output) == ["Unrelated", "A reply"])
        #expect(drafts.map(\.input) == ["someone else's words", ""])
    }

    @Test func historyMixesDictationsAndDraftsNewestFirstWithYourEdits() throws {
        let store = try HistoryStore()
        let anna = try store.drafts.thread(app: "com.tinyspeck.slackmacgap", title: "Anna").id
        var dictated = makeRecord("on my way", at: 1)
        dictated.threadID = anna
        try store.insert(dictated)
        try store.insert(makeRecord("elsewhere", at: 2))
        try store.insert(TranscriptRecord(ExtensionHistoryEntry(extension: "meetings", text: "a meeting", seconds: 60, file: nil)))
        let draft = makeDraft("See you at 1!", at: 3, thread: anna)
        try store.drafts.insert(draft)
        try store.drafts.finish(draft.id, result: "see you at 1", outcome: .edited)
        try store.drafts.insert(makeDraft("Fixed the typo.", source: "edit", at: 4))

        let all = try store.drafts.written(limit: 10)
        #expect(all.map(\.text) == ["Fixed the typo.", "see you at 1", "elsewhere", "on my way"])
        #expect(all[1] == WrittenText(kind: .draft, text: "see you at 1", at: 3000, thread: anna, source: "reply", instruction: nil, input: "", output: "See you at 1!", outcome: .edited, app: "com.tinyspeck.slackmacgap", threadTitle: "Anna"))
        #expect(all[0].outcome == .unknown)
        #expect(try store.drafts.written(thread: anna, limit: 10).map(\.text) == ["see you at 1", "on my way"])
        #expect(try store.drafts.written(source: "edit", limit: 10).map(\.text) == ["Fixed the typo."])
        #expect(try store.drafts.written(limit: 2).map(\.text) == ["Fixed the typo.", "see you at 1"])
        #expect(try store.drafts.written(limit: 1000).count == 4)
    }

    @Test func aDraftLinksToTheDictationItReplaced() throws {
        let store = try HistoryStore()
        var old = makeRecord("lunch at one", at: 1)
        old.finalText = "Lunch at one."
        try store.insert(old)
        let recent = makeRecord("Lunch at one.", at: 100)
        try store.insert(recent)
        #expect(try store.drafts.transcriptID(replacedBy: " Lunch at one. ", since: epoch(50)) == recent.id)
        #expect(try store.drafts.transcriptID(replacedBy: "Lunch at two.", since: epoch(0)) == nil)
        #expect(try store.drafts.transcriptID(replacedBy: "", since: epoch(0)) == nil)
    }

    @Test func deletingADictationKeepsTheDraftsThatReplacedIt() throws {
        let store = try HistoryStore()
        let record = makeRecord("hello", at: 1)
        try store.insert(record)
        var draft = makeDraft("Hello.", source: "edit", at: 2, input: "hello")
        draft.transcriptID = record.id
        try store.drafts.insert(draft)
        try store.delete(id: record.id)
        #expect(try store.drafts.recent(limit: 10).map(\.draft.transcriptID) == [nil])
    }
}

@Suite struct ThreadTitleTests {
    @Test(arguments: [
        ("(3) Anna Schmidt - Slack", "Slack", "Anna Schmidt"),
        ("● design-review | Slack", "Slack", "design-review"),
        ("Anna — WhatsApp", "WhatsApp", "Anna"),
        ("Inbox - anna@example.com - Gmail - Google Chrome", "Google Chrome", "Inbox - anna@example.com - Gmail"),
        ("Messages", "Messages", nil),
        ("(3) Slack", "Slack", nil),
        ("  ", "Notes", nil),
        ("(12+) ", "Mail", nil),
    ])
    func titlesDropUnreadCountsAndTheAppName(window: String, app: String, title: String?) {
        #expect(ThreadRecord.title(fromWindow: window, appName: app) == title)
    }
}

@Suite struct DraftTraceTests {
    private let output = "See you at 1!"

    @Test func readsWhatYouDidWithTheDraft() throws {
        let trace = try #require(DraftTrace(output: output, field: "Hi Anna, See you at 1! -J"))
        #expect(trace.draft(in: "Hi Anna, See you at 1! -J") == output)
        #expect(trace.draft(in: "Hi Anna, see you at one -J") == "see you at one")
        #expect(trace.draft(in: "Hi Anna, See you at 1!! -J") == "See you at 1!!")
        #expect(trace.draft(in: "Hi Anna,  -J") == "")
        #expect(trace.draft(in: "Hey Anna, See you at 1! -J") == output)
        #expect(trace.draft(in: "Hi Anna, See you at 1! Bring slides -J") == output)
    }

    @Test func aFieldWithoutTheDraftHasNoTrace() {
        #expect(DraftTrace(output: output, field: "something else") == nil)
        #expect(DraftTrace(output: "", field: "anything") == nil)
    }

    @Test func outcomesCompareTrimmedText() {
        #expect(DraftTrace.outcome(output: output, result: " See you at 1! ") == .kept)
        #expect(DraftTrace.outcome(output: output, result: "see you at one") == .edited)
        #expect(DraftTrace.outcome(output: output, result: "  ") == .removed)
    }
}
