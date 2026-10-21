import Testing
@testable import VozCore

@Suite struct TextTransformTests {
    @Test func fillersGoButWordsThatContainThemStay() {
        #expect(FillerWords.removeObvious(from: "so uh I think, uhm, we should go") == FillerPassResult(text: "So I think, we should go", removed: 2))
        #expect(FillerWords.removeObvious(from: "ähm ich glaube äh wir sollten gehen") == FillerPassResult(text: "Ich glaube wir sollten gehen", removed: 2))
        #expect(FillerWords.removeObvious(from: "Um, we should go").text == "We should go")
        #expect(FillerWords.removeObvious(from: "um so I was thinking we should move the meeting") == FillerPassResult(text: "So I was thinking we should move the meeting", removed: 1))
        #expect(FillerWords.removeObvious(from: "does it do like um redoing the prompt").text == "Does it do like redoing the prompt")
        for kept in ["Wir treffen uns um 4 Uhr.", "um 3 Uhr", "um das zu machen brauchen wir Zeit", "The umbrella is humming under the umlaut"] {
            #expect(FillerWords.removeObvious(from: kept) == FillerPassResult(text: kept, removed: 0))
        }
        #expect(FillerWords.estimateRemoved(before: "um so you know I mean it was like fine", after: "So it was fine.") == 4)
        #expect(FillerWords.estimateRemoved(before: "at 3, no, 4", after: "at 4") == 0)
    }

    @Test func spokenPunctuationConvertsCommandsButNotMentions() {
        #expect(SpokenPunctuation.apply(to: "hi John comma thanks for the update period new line talk soon") == "hi John, thanks for the update.\nTalk soon")
        #expect(SpokenPunctuation.apply(to: "hallo Maria Komma danke für die Nachricht Punkt neue Zeile viele Grüße Tom") == "hallo Maria, danke für die Nachricht.\nViele Grüße Tom")
        #expect(SpokenPunctuation.apply(to: "kommst du morgen Fragezeichen") == "kommst du morgen?")
        #expect(SpokenPunctuation.apply(to: "done full stop new paragraph next topic") == "done.\n\nNext topic")
        #expect(SpokenPunctuation.apply(to: "Thanks Sam, comma see you") == "Thanks Sam, see you")
        #expect(SpokenPunctuation.apply(to: "set NODE underscore ENV to production") == "set NODE_ENV to production")
        #expect(SpokenPunctuation.apply(to: "die Datei heißt backup unterstrich alt") == "die Datei heißt backup_alt")
        let literal = [
            "the word comma is spelled with two m's",
            "a long period of time",
            "this is a new line of code",
            "bis zu diesem Punkt war alles klar",
            "wir treffen uns Punkt drei Uhr",
            "drei Komma fünf Prozent",
            "he said \"comma\" twice",
            "period",
            "underscore",
        ]
        for text in literal {
            #expect(SpokenPunctuation.apply(to: text) == text)
        }
    }

    @Test func vocabularyFixesCasingOfWholeWordsAndSpliceKeepsPunctuation() {
        #expect(VocabularyCasing.apply(["Kubernetes", "PostHog"], to: "we run kubernetes and posthog") == "we run Kubernetes and PostHog")
        #expect(VocabularyCasing.apply(["Helm"], to: "the helmet and helm") == "the helmet and Helm")
        #expect(VocabularyCasing.apply(["C++"], to: "i like c++ a lot") == "i like C++ a lot")
        let edits = [TextEdit(utf8Range: 5..<8, replacement: "Voz"), TextEdit(utf8Range: 21..<24, replacement: "Voz")]
        #expect(TextSplice.apply(edits, to: "Open Vos, then close Vos.") == "Open Voz, then close Voz.")
        #expect(TextSplice.apply([TextEdit(utf8Range: 8..<11, replacement: "Voz")], to: "Grüße Vos") == "Grüße Voz")
        let unsafe = [TextEdit(utf8Range: 1..<4, replacement: "X"), TextEdit(utf8Range: 3..<5, replacement: "Y"), TextEdit(utf8Range: 5..<99, replacement: "Z")]
        #expect(TextSplice.apply(unsafe, to: "abcdef") == "abcYf")
    }

    @Test func sentenceChunksSplitLosslesslyAtSentencesAndLines() {
        let sentence = "This sentence has exactly ten words in it for sure. "
        let long = String(repeating: sentence, count: 12)
        let chunks = SentenceChunks.split(long, targetWords: 30)
        #expect(chunks.joined() == long)
        #expect(chunks.count > 1)
        #expect(chunks.allSatisfy { $0.hasSuffix(". ") })
        #expect(SentenceChunks.split("One short sentence. And another one here.") == ["One short sentence. And another one here."])
        #expect(SentenceChunks.split(String(repeating: "word ", count: 35) + "end.", targetWords: 35).count == 1)
        let lines = SentenceChunks.split("first line has plenty of words in it\nsecond line also has plenty of words here too", targetWords: 9)
        #expect(lines == ["first line has plenty of words in it\n", "second line also has plenty of words here too"])
        #expect(SentenceChunks.split("").isEmpty)
    }

    @Test func segmentsJoinWithFallbackPerSegmentAndNoStrayPeriods() {
        #expect(SegmentJoiner.join([" First one. ", "", "Second one.\n"]) == "First one. Second one.")
        #expect(SegmentJoiner.join(cleaned: ["Clean one.", nil, "Clean three."], fallback: ["raw one.", "rule two.", "raw three"]) == "Clean one. rule two. Clean three.")
        #expect(SegmentJoiner.join(cleaned: ["We went to.", "the store today."], fallback: ["we went to", "the store today."]) == "We went to the store today.")
        #expect(SegmentJoiner.join(cleaned: ["We left.", "Then it rained."], fallback: ["we left.", "then it rained."]) == "We left. Then it rained.")
        #expect(SegmentJoiner.join(cleaned: ["We left."], fallback: ["we left"]) == "We left.")
    }

    @Test func cleanupRulesRunOnlyListedStepsInOrder() {
        let raw = "uh send it to voz comma please"
        #expect(CleanupStep.applyRules(CleanupStep.standard, to: raw, vocabulary: ["Voz"]) == FillerPassResult(text: "Send it to Voz, please", removed: 1))
        #expect(CleanupStep.applyRules(["punctuation", "llm/jira", "model"], to: raw, vocabulary: ["Voz"]).text == "uh send it to voz, please")
        #expect(CleanupStep.applyRules([], to: raw, vocabulary: ["Voz"]) == FillerPassResult(text: raw, removed: 0))
    }
}
