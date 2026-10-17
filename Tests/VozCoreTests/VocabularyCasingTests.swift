import Testing
@testable import VozCore

@Suite struct VocabularyCasingTests {
    @Test func fixesCasingOfWholeWords() {
        #expect(VocabularyCasing.apply(["Kubernetes", "PostHog"], to: "we run kubernetes and posthog") == "we run Kubernetes and PostHog")
    }

    @Test func ignoresWordsInsideOtherWords() {
        #expect(VocabularyCasing.apply(["Helm"], to: "the helmet and helm") == "the helmet and Helm")
    }

    @Test func handlesRegexCharactersInWords() {
        #expect(VocabularyCasing.apply(["C++"], to: "i like c++ a lot") == "i like C++ a lot")
    }

    @Test func leavesTextAloneWithoutVocabulary() {
        #expect(VocabularyCasing.apply([], to: "hello") == "hello")
    }
}
