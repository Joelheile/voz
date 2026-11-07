import Testing
@testable import Voz

@MainActor @Suite struct AppSearchTests {
    private func results(_ query: String, words: [String] = [], extensions: [AppSearchExtension] = [], transcripts: [TranscriptRecord] = []) -> [AppSearchItem] {
        AppSearch.results(for: query, words: words, extensions: extensions, transcripts: transcripts, now: epoch(1_000))
    }

    @Test func withNothingTypedItOffersThePlacesYouCanGo() {
        let found = results("  ", words: ["Parakeet"], transcripts: [makeRecord("hello", at: 0)])
        #expect(found.contains { $0.target == .page(.insights) })
        #expect(found.allSatisfy { $0.section == .app })
    }

    @Test func aSettingIsFoundByTheWordYouThinkOf() {
        #expect(results("hotkey").first?.title == "Shortcut")
        #expect(results("hotkey").first?.target == .page(.settings))
        #expect(results("clipboard").first?.title == "Output")
    }

    @Test func allTermsHaveToMatch() {
        #expect(results("cleanup prompt").map(\.title) == ["Cleanup prompt"])
        #expect(results("cleanup zebra").isEmpty)
    }

    @Test func extensionsAreFoundByNameOrSummary() {
        let tone = AppSearchExtension(name: "voz-tone", summary: "Rewrites your text in a friendlier way")
        #expect(results("tone", extensions: [tone]).first?.target == .extensionNamed("voz-tone"))
        #expect(results("friendlier", extensions: [tone]).first?.target == .extensionNamed("voz-tone"))
    }

    @Test func dictionaryWordsOpenTheDictionary() {
        let found = results("grdb", words: ["GRDB", "Sparkle"])
        #expect(found.map(\.title) == ["GRDB"])
        #expect(found.first?.section == .dictionary)
        #expect(found.first?.target == .page(.dictionary))
    }

    @Test func placesComeBeforeTranscriptsAndTranscriptsAreKeptAsMatched() {
        let record = makeRecord("Book the dictionary review", at: 0)
        let found = results("dictionary", transcripts: [record])
        #expect(found.first?.target == .page(.dictionary))
        #expect(found.last?.target == .transcript(record.id))
        #expect(found.last?.section == .transcripts)
    }

    @Test func aLongListOfTranscriptsIsCut() {
        let records = (0..<30).map { makeRecord("note \($0)", at: Double($0)) }
        #expect(results("zzz", transcripts: records).count == 20)
    }

    @Test func everyResultHasItsOwnID() {
        let found = results("e", words: ["Sparkle"], transcripts: [makeRecord("one", at: 0), makeRecord("one", at: 1)])
        #expect(Set(found.map(\.id)).count == found.count)
    }
}

@MainActor @Suite struct SearchShortcutTests {
    @Test func commandFGoesHomeAndAsksForTheSearchBox() {
        let model = PopoverModel()
        model.page = .settings
        model.focusTranscriptSearch()
        #expect(model.page == .home)
        #expect(model.searchFocusRequests == 1)
        model.focusTranscriptSearch()
        #expect(model.searchFocusRequests == 2, "pressing it again on home still moves the cursor back")
    }

    @Test func commandKOpensAndClosesEverythingSearch() {
        let model = PopoverModel()
        model.page = .dictionary
        model.toggleEverythingSearch()
        #expect(model.page == .search)
        model.toggleEverythingSearch()
        #expect(model.page == .home)
    }
}
