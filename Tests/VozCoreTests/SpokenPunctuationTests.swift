import Testing
@testable import VozCore

@Suite struct SpokenPunctuationTests {
    @Test func convertsEnglishCommands() {
        #expect(SpokenPunctuation.apply(to: "hi John comma thanks for the update period new line talk soon") == "hi John, thanks for the update.\nTalk soon")
    }

    @Test func convertsGermanCommands() {
        #expect(SpokenPunctuation.apply(to: "hallo Maria Komma danke für die Nachricht Punkt neue Zeile viele Grüße Tom") == "hallo Maria, danke für die Nachricht.\nViele Grüße Tom")
    }

    @Test func convertsQuestionMarks() {
        #expect(SpokenPunctuation.apply(to: "are you coming tomorrow question mark") == "are you coming tomorrow?")
        #expect(SpokenPunctuation.apply(to: "kommst du morgen Fragezeichen") == "kommst du morgen?")
    }

    @Test func convertsParagraphsAndFullStop() {
        #expect(SpokenPunctuation.apply(to: "done full stop new paragraph next topic") == "done.\n\nNext topic")
        #expect(SpokenPunctuation.apply(to: "fertig Punkt neuer Absatz weiter") == "fertig.\n\nWeiter")
    }

    @Test func replacesPunctuationAlreadyOnPreviousWord() {
        #expect(SpokenPunctuation.apply(to: "Thanks Sam, comma see you") == "Thanks Sam, see you")
    }

    @Test func keepsLiteralMentions() {
        let literal = [
            "the word comma is spelled with two m's",
            "the period of time was long",
            "a long period of time",
            "this is a new line of code",
            "that was the question mark key",
            "bis zu diesem Punkt war alles klar",
            "wir treffen uns Punkt drei Uhr",
            "drei Komma fünf Prozent",
            "he said \"comma\" twice",
            "period",
        ]
        for text in literal {
            #expect(SpokenPunctuation.apply(to: text) == text)
        }
    }

    @Test func leavesTextWithoutCommandsUnchanged() {
        let text = "Wir treffen uns um halb drei im Büro."
        #expect(SpokenPunctuation.apply(to: text) == text)
    }
}
