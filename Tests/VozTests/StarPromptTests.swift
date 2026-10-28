import Testing
@testable import Voz

@Suite struct StarPromptTests {
    @Test func showsOnceTheUserHasDictatedEnoughWords() {
        #expect(!StarPrompt.shows(words: 1_999, dismissed: false))
        #expect(StarPrompt.shows(words: 2_000, dismissed: false))
        #expect(!StarPrompt.shows(words: 50_000, dismissed: true))
    }
}
