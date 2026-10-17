import Testing
@testable import VozCore

@Suite struct FillerWordsTests {
    @Test func removesUnambiguousEnglishFillers() {
        let result = FillerWords.removeObvious(from: "so uh I think, uhm, we should go")
        #expect(result.text == "So I think, we should go")
        #expect(result.removed == 2)
    }

    @Test func removesGermanFillers() {
        let result = FillerWords.removeObvious(from: "ähm ich glaube äh wir sollten gehen")
        #expect(result.text == "Ich glaube wir sollten gehen")
        #expect(result.removed == 2)
    }

    @Test func keepsGermanPrepositionUm() {
        let text = "Wir treffen uns um 4 Uhr."
        #expect(FillerWords.removeObvious(from: text) == FillerPassResult(text: text, removed: 0))
    }

    @Test func removesUmOnlyWhenPunctuated() {
        #expect(FillerWords.removeObvious(from: "Um, we should go").text == "We should go")
        #expect(FillerWords.removeObvious(from: "um 3 Uhr").removed == 0)
    }

    @Test func keepsWordsContainingFillers() {
        let text = "The umbrella is humming under the umlaut"
        #expect(FillerWords.removeObvious(from: text).removed == 0)
    }

    @Test func estimatesRemovedFillersFromWordDiff() {
        let removed = FillerWords.estimateRemoved(
            before: "um so you know I mean it was like fine",
            after: "So it was fine."
        )
        #expect(removed == 4)
    }

    @Test func doesNotCountSelfCorrectionAsFiller() {
        #expect(FillerWords.estimateRemoved(before: "at 3, no, 4", after: "at 4") == 0)
    }

    @Test func estimatesGermanFillers() {
        #expect(FillerWords.estimateRemoved(before: "ich glaube halt sozusagen es geht", after: "Ich glaube es geht.") == 2)
    }
}
