import Testing
@testable import VozCore

struct VoiceCommandsTests {
    @Test func wholeUtteranceMatchesWithNoLeadingText() {
        #expect(VoiceCommands.match("Send it.", phrases: ["send it"]) == VoiceCommandMatch(phrase: "send it", leadingText: ""))
    }

    @Test func trailingPhraseSplitsOffTheDictatedText() {
        let match = VoiceCommands.match("Thanks for the update. Send it.", phrases: ["send it"])
        #expect(match == VoiceCommandMatch(phrase: "send it", leadingText: "Thanks for the update."))
    }

    @Test func trailingCommaBeforeThePhraseIsDropped() {
        let match = VoiceCommands.match("Sounds good, send it", phrases: ["send it"])
        #expect(match == VoiceCommandMatch(phrase: "send it", leadingText: "Sounds good"))
    }

    @Test func phraseInTheMiddleDoesNotMatch() {
        #expect(VoiceCommands.match("Send it to Anna tomorrow.", phrases: ["send it"]) == nil)
    }

    @Test func longestPhraseWins() {
        let match = VoiceCommands.match("Okay, send it now!", phrases: ["now", "send it now"])
        #expect(match == VoiceCommandMatch(phrase: "send it now", leadingText: "Okay"))
    }

    @Test func matchingIgnoresCaseAndPunctuationInPhrases() {
        #expect(VoiceCommands.match("NEW LINE", phrases: ["New line!"])?.phrase == "New line!")
    }

    @Test func partialWordsDoNotMatch() {
        #expect(VoiceCommands.match("I resend it", phrases: ["send it"]) == nil)
    }
}
