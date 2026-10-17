import Testing
@testable import VozCore

@Suite struct VocabularyStoreTests {
    @Test func listsWordsAlphabeticallyIgnoringCaseInsensitiveDuplicates() throws {
        let store = try HistoryStore().vocabulary
        try store.add("voz", source: .manual)
        try store.add("PostHog", source: .manual)
        try store.add("VOZ", source: .manual)
        #expect(try store.words() == ["PostHog", "voz"])
    }

    @Test func acceptingSuggestionMovesItToVocabularyAsLearned() throws {
        let store = try HistoryStore().vocabulary
        try store.suggest("Kubernetes")
        let pending = try #require(try observed(store).suggestions.first)
        try store.accept(pending)
        let snapshot = try observed(store)
        #expect(snapshot.suggestions.isEmpty)
        #expect(snapshot.words.map(\.word) == ["Kubernetes"])
        #expect(snapshot.words.first?.source == .learned)
    }

    @Test func dismissingSuggestionRemovesIt() throws {
        let store = try HistoryStore().vocabulary
        try store.suggest("Kubernetes")
        try store.dismiss(try #require(try observed(store).suggestions.first))
        #expect(try observed(store).suggestions.isEmpty)
    }

    @Test func doesNotSuggestKnownOrPendingWords() throws {
        let store = try HistoryStore().vocabulary
        try store.add("voz", source: .manual)
        try store.suggest("Voz")
        try store.suggest("Kubernetes")
        try store.suggest("kubernetes")
        #expect(try observed(store).suggestions.map(\.word) == ["Kubernetes"])
    }

    @Test func removesWord() throws {
        let store = try HistoryStore().vocabulary
        try store.add("voz", source: .manual)
        let word = try #require(try observed(store).words.first)
        try store.remove(id: word.id)
        #expect(try store.words().isEmpty)
    }

    private func observed(_ store: VocabularyStore) throws -> VocabularySnapshot {
        try store.snapshot()
    }
}
