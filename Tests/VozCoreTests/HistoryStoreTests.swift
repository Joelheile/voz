import Testing
@testable import VozCore

@Suite struct HistoryStoreTests {
    @Test func newestFirstAndLimited() throws {
        let store = try HistoryStore()
        for index in 1...12 { try store.insert(makeRecord("t\(index)", at: Double(index))) }
        let recent = try store.recent(limit: 10)
        #expect(recent.count == 10)
        #expect(recent.first?.finalText == "t12")
        #expect(recent.last?.finalText == "t3")
    }

    @Test func searchIsCaseInsensitiveOverFinalText() throws {
        let store = try HistoryStore()
        try store.insert(makeRecord("Hello World", at: 1))
        try store.insert(makeRecord("goodbye", at: 2))
        try store.insert(makeRecord("Über Straße", at: 3))
        #expect(try store.search("hello").map(\.finalText) == ["Hello World"])
        #expect(try store.search("WORLD").count == 1)
        #expect(try store.search("über").count == 1)
        #expect(try store.search("").count == 3)
        #expect(try store.search("  ").count == 3)
        #expect(try store.search("missing").isEmpty)
    }

    @Test func searchTreatsLikeWildcardsLiterally() throws {
        let store = try HistoryStore()
        try store.insert(makeRecord("100% done"))
        try store.insert(makeRecord("plain"))
        #expect(try store.search("%").map(\.finalText) == ["100% done"])
        #expect(try store.search("_").isEmpty)
    }

    @Test func searchMatchesFinalNotRawText() throws {
        let store = try HistoryStore()
        var cleaned = makeRecord("um hello there")
        cleaned.finalText = "Hello there."
        try store.insert(cleaned)
        #expect(try store.search("um").isEmpty)
        #expect(try store.search("hello").count == 1)
    }

    @Test func deleteRemovesOnlyThatRow() throws {
        let store = try HistoryStore()
        let first = makeRecord("one", at: 1)
        try store.insert(first)
        try store.insert(makeRecord("two", at: 2))
        try store.delete(id: first.id)
        #expect(try store.recent().map(\.finalText) == ["two"])
    }

    @Test func recordKeepsSchemaFields() throws {
        let store = try HistoryStore()
        try store.insert(makeRecord("one two three"))
        let saved = try #require(try store.recent().first)
        #expect(saved.rawText == saved.finalText)
        #expect(saved.wordCount == 3)
        #expect(saved.appBundleID == "com.apple.Notes")
        #expect(saved.fillerWordsRemoved == 0)
    }

    @Test func persistsOnDisk() throws {
        let path = makeTemporaryStorePath()
        defer { removeFile(atPath: path) }
        try HistoryStore(path: path).insert(makeRecord("kept"))
        #expect(try HistoryStore(path: path).recent().count == 1)
    }
}
