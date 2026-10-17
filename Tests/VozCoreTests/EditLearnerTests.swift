import Testing
@testable import VozCore

@Suite struct EditLearnerTests {
    private let knowsEverything: (String) -> Bool = { _ in true }
    private let knowsNothing: (String) -> Bool = { _ in false }

    private func learn(_ inserted: String, _ current: String, known: (String) -> Bool) -> [String] {
        EditLearner.suggestions(inserted: inserted, current: current, isKnownWord: known)
    }

    @Test func learnsCapitalizedReplacement() {
        #expect(learn("open vos and start", "open Voz and start", known: knowsEverything) == ["Voz"])
    }

    @Test func learnsReplacementSurroundedByOtherFieldText() {
        #expect(learn("open vos and start", "Notes: open Voz and start now", known: knowsEverything) == ["Voz"])
    }

    @Test func learnsWordWithDigits() {
        #expect(learn("use the gpt four model", "use the gpt4 model", known: knowsEverything).isEmpty)
        #expect(learn("use the gptfour model", "use the gpt4 model", known: knowsEverything) == ["gpt4"])
    }

    @Test func learnsCamelCase() {
        #expect(learn("we use post hog daily", "we use postHog daily", known: knowsEverything).isEmpty)
        #expect(learn("we use poshog daily", "we use postHog daily", known: knowsEverything) == ["postHog"])
    }

    @Test func learnsWordUnknownToSpellChecker() {
        #expect(learn("call the kubernetis cluster", "call the kubernetes cluster", known: knowsNothing) == ["kubernetes"])
    }

    @Test func ignoresCommonWordReplacement() {
        #expect(learn("we should go there", "we should walk there", known: knowsEverything).isEmpty)
    }

    @Test func ignoresPunctuationOnlyChange() {
        #expect(learn("hello world", "hello, world.", known: knowsNothing).isEmpty)
    }

    @Test func ignoresPureInsertionsAndDeletions() {
        #expect(learn("one two three", "one three", known: knowsNothing).isEmpty)
        #expect(learn("one two three", "one two Extra three", known: knowsNothing).isEmpty)
    }

    @Test func ignoresUnchangedText() {
        #expect(learn("Open Voz now", "Open Voz now", known: knowsNothing).isEmpty)
    }

    @Test func returnsEmptyForEmptyField() {
        #expect(learn("Open Voz now", "", known: knowsNothing).isEmpty)
    }
}
