import Testing
@testable import VozCore

@Suite struct SentenceChunksTests {
    @Test func keepsShortTextInOneChunk() {
        let text = "One short sentence. And another one here."
        #expect(SentenceChunks.split(text) == [text])
    }

    @Test func joinsBackToTheOriginal() {
        let sentence = "This sentence has exactly ten words in it for sure. "
        let text = String(repeating: sentence, count: 12)
        let chunks = SentenceChunks.split(text, targetWords: 30)
        #expect(chunks.joined() == text)
        #expect(chunks.count > 1)
    }

    @Test func groupsWholeSentencesUpToTheTarget() {
        let sentence = "This sentence has exactly ten words in it for sure. "
        let chunks = SentenceChunks.split(String(repeating: sentence, count: 6), targetWords: 30)
        #expect(chunks.count == 2)
        #expect(chunks.allSatisfy { $0.hasSuffix(". ") })
    }

    @Test func splitsLongTextWithoutPunctuationByWordCount() {
        let words = Array(repeating: "word", count: 100).joined(separator: " ")
        let chunks = SentenceChunks.split(words, targetWords: 40)
        #expect(chunks.joined() == words)
        #expect(chunks.count == 2 || chunks.count == 3)
    }

    @Test func mergesTinyTailIntoPreviousChunk() {
        let text = String(repeating: "word ", count: 35) + "end."
        #expect(SentenceChunks.split(text, targetWords: 35).count == 1)
    }

    @Test func splitsAtNewlines() {
        let chunks = SentenceChunks.split("first line has plenty of words in it\nsecond line also has plenty of words here too", targetWords: 9)
        #expect(chunks == ["first line has plenty of words in it\n", "second line also has plenty of words here too"])
    }

    @Test func returnsNothingForEmptyText() {
        #expect(SentenceChunks.split("").isEmpty)
    }
}
