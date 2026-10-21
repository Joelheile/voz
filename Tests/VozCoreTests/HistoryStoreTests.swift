import Testing
import VozCore

@Suite struct HistoryStoreTests {
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
