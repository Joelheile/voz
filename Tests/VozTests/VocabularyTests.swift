import Testing
@testable import Voz

@Suite struct EditLearnerTests {
    private let dictionary: Set<String> = ["practices", "glide", "the", "we", "use", "good", "great", "next"]

    private func suggestions(_ inserted: String, _ current: String) -> [VocabularyCandidate] {
        EditLearner.suggestions(inserted: inserted, current: current) { dictionary.contains($0.lowercased()) }
    }

    @Test func ignoresCapitalizedDictionaryWords() {
        #expect(suggestions("practices we use", "Practices we use").isEmpty)
        #expect(suggestions("we use slide", "we use Glide").isEmpty)
    }

    @Test func learnsOnlyReplacementsThatSoundLikeTheOriginal() {
        #expect(suggestions("we use Superbass", "we use Supabase") == [VocabularyCandidate(word: "Supabase", heardAs: "Superbass")])
        #expect(suggestions("we use voss", "we use Voz") == [VocabularyCandidate(word: "Voz", heardAs: "voss")])
        #expect(suggestions("we use slack", "we use Mastra").isEmpty)
    }
}

@Suite struct VocabularyAliasTests {
    @Test func acceptedSuggestionKeepsHowTheWordWasMisheard() throws {
        let vocabulary = try HistoryStore().vocabulary
        try vocabulary.suggest("Supabase", aliases: ["Superbass"])
        let suggestion = try #require(vocabulary.snapshot().suggestions.first)
        try vocabulary.accept(suggestion)
        try vocabulary.add("Voz", source: .manual)
        #expect(try vocabulary.terms() == [
            VocabularyTerm(word: "Supabase", aliases: ["Superbass"]),
            VocabularyTerm(word: "Voz", aliases: []),
        ])
    }
}

@Suite struct SpokenCandidatesTests {
    private func find(_ text: String) -> [VocabularyCandidate] {
        SpokenCandidates.find(in: text) { ["good", "great", "we", "use"].contains($0.lowercased()) }
    }

    @Test func joinsSpelledLettersIntoOneWord() {
        #expect(find("It's called G R O K, the bot.") == [VocabularyCandidate(word: "Grok", heardAs: "G R O K")])
        #expect(find("I think a b is fine").isEmpty)
        #expect(find("pick option A, B, C or D").isEmpty)
        #expect(find("it is spelled G O O D").isEmpty)
    }

    @Test func learnsFromSpokenCorrectionsThatSoundAlike() {
        #expect(find("we use Superbass, no, not Superbass, Supabase.") == [VocabularyCandidate(word: "Supabase", heardAs: "Superbass")])
        #expect(find("it was good, not good, great").isEmpty)
    }
}

@Suite struct VocabularyLearnerTests {
    private let voz = VocabularyCandidate(word: "Voz", heardAs: "voss")
    private let supabase = VocabularyCandidate(word: "Supabase", heardAs: "Superbass")

    @Test func addsWhatTheSpeechModelHearsAsAnAliasWhenItDiffers() async throws {
        let vocabulary = try HistoryStore().vocabulary
        let learner = VocabularyLearner(store: vocabulary, hear: { $0 == "Voz" ? "Voz." : "Super base." })
        await learner.consider([voz, supabase])
        let suggestions = try vocabulary.snapshot().suggestions.sorted { $0.word < $1.word }
        #expect(suggestions.map(\.word) == ["Supabase", "Voz"])
        #expect(suggestions.map(\.aliases) == [["Superbass", "Super base"], ["voss"]])
    }

    @Test func suggestsWithTheCorrectedFormWhenTheSpeechModelIsUnavailable() async throws {
        let vocabulary = try HistoryStore().vocabulary
        let learner = VocabularyLearner(store: vocabulary, hear: { _ in nil })
        await learner.consider([supabase])
        #expect(try vocabulary.snapshot().suggestions.map(\.aliases) == [["Superbass"]])
    }
}

@Suite struct VocabularyReplacementTests {
    @Test func replacesWholeWordsIgnoringCase() {
        let rules = [VocabularyRule(heard: "voss", word: "Voz")]
        #expect(VocabularyRule.apply(rules, to: "Voss said vossberg uses voss.") == "Voz said vossberg uses Voz.")
    }

    @Test func aRepeatedCorrectionOfAKnownWordBecomesARule() async throws {
        let vocabulary = try HistoryStore().vocabulary
        try vocabulary.add("Voz", source: .learned, aliases: ["voss"])
        let learner = VocabularyLearner(store: vocabulary, hear: { _ in nil })
        await learner.consider([VocabularyCandidate(word: "Voz", heardAs: "Vos")])
        #expect(try vocabulary.rules() == [VocabularyRule(heard: "Vos", word: "Voz")])
        #expect(try vocabulary.terms() == [VocabularyTerm(word: "Voz", aliases: ["voss", "Vos"])])
    }

    @Test func aPendingSuggestionDoesNotBecomeARule() async throws {
        let vocabulary = try HistoryStore().vocabulary
        try vocabulary.suggest("Voz", aliases: ["voss"])
        await VocabularyLearner(store: vocabulary, hear: { _ in nil }).consider([VocabularyCandidate(word: "Voz", heardAs: "voss")])
        #expect(try vocabulary.rules().isEmpty)
    }

    @Test func editingTheWordBackRemovesTheRule() async throws {
        let vocabulary = try HistoryStore().vocabulary
        try vocabulary.add("voss -> Voz", source: .manual)
        let edits = EditLearner.edits(inserted: "ask Voz", current: "ask voss")
        await VocabularyLearner(store: vocabulary, hear: { _ in nil }).forget(edits)
        #expect(try vocabulary.rules().isEmpty)
        #expect(try vocabulary.words() == ["Voz"])
    }

    @Test func typingAnArrowAddsTheWordWithARule() throws {
        let vocabulary = try HistoryStore().vocabulary
        try vocabulary.add("voss -> Voz", source: .manual)
        try vocabulary.add("superbass → Supabase", source: .manual)
        try vocabulary.add("Mastra", source: .manual)
        #expect(try vocabulary.rules() == [
            VocabularyRule(heard: "superbass", word: "Supabase"),
            VocabularyRule(heard: "voss", word: "Voz"),
        ])
        #expect(try vocabulary.words() == ["Mastra", "Supabase", "Voz"])
    }
}
