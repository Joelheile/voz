import Testing
@testable import Voz

@Suite struct TextTransformTests {
    @Test func fillersGoButWordsThatContainThemStay() {
        #expect(FillerWords.removeObvious(from: "so uh I think, uhm, we should go") == RulePassResult(text: "So I think, we should go", removed: 2))
        #expect(FillerWords.removeObvious(from: "ähm ich glaube äh wir sollten gehen") == RulePassResult(text: "Ich glaube wir sollten gehen", removed: 2))
        #expect(FillerWords.removeObvious(from: "Um, we should go").text == "We should go")
        #expect(FillerWords.removeObvious(from: "um so I was thinking we should move the meeting") == RulePassResult(text: "So I was thinking we should move the meeting", removed: 1))
        #expect(FillerWords.removeObvious(from: "does it do like um redoing the prompt").text == "Does it do like redoing the prompt")
        for kept in ["Wir treffen uns um 4 Uhr.", "um 3 Uhr", "um das zu machen brauchen wir Zeit", "The umbrella is humming under the umlaut"] {
            #expect(FillerWords.removeObvious(from: kept) == RulePassResult(text: kept, removed: 0))
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

    @Test func segmentsJoinWithFallbackPerSegmentAndNoStrayPeriods() {
        #expect(SegmentJoiner.join([" First one. ", "", "Second one.\n"]) == "First one. Second one.")
        #expect(SegmentJoiner.join(cleaned: ["Clean one.", nil, "Clean three."], fallback: ["raw one.", "rule two.", "raw three"]) == "Clean one. rule two. Clean three.")
        #expect(SegmentJoiner.join(cleaned: ["We went to.", "the store today."], fallback: ["we went to", "the store today."]) == "We went to the store today.")
        #expect(SegmentJoiner.join(cleaned: ["We left.", "Then it rained."], fallback: ["we left.", "then it rained."]) == "We left. Then it rained.")
        #expect(SegmentJoiner.join(cleaned: ["We left."], fallback: ["we left"]) == "We left.")
    }

    @Test func cleanupRulesRunOnlyListedStepsInOrder() {
        let raw = "uh send it to voz comma please"
        #expect(CleanupStep.applyRules(CleanupStep.standard, to: raw, vocabulary: ["Voz"]) == RulePassResult(text: "Send it to Voz, please", removed: 1))
        #expect(CleanupStep.applyRules(["punctuation", "llm/jira", "model"], to: raw, vocabulary: ["Voz"]).text == "uh send it to voz, please")
        #expect(CleanupStep.applyRules([], to: raw, vocabulary: ["Voz"]) == RulePassResult(text: raw, removed: 0))
    }
}

@Suite struct CleanupWorkTests {
    @Test func finishedSentencesWithNothingToFixSkipTheModel() {
        #expect(!CleanupWork.needsModel("I think context is even more expensive."))
        #expect(!CleanupWork.needsModel("Was genau würdest du entfernen?"))
        #expect(CleanupWork.needsModel("So like we should ship."))
        #expect(CleanupWork.needsModel("Send it to Tom, sorry, Tim."))
        #expect(CleanupWork.needsModel("It costs twenty euros."))
        #expect(CleanupWork.needsModel("The the plan is ready."))
        #expect(CleanupWork.needsModel("Mail me at joel dot com."))
        #expect(CleanupWork.needsModel("I think we should"))
        #expect(CleanupWork.needsModel("and then we ship."))
    }

    @MainActor @Test func onlyTheStandardPromptSkipsTheModel() async {
        let calls = CallCount()
        let extensions = CleanupExtensions(model: { text, _, _ in
            calls.count += 1
            return text
        }) { _, text, _ in text }
        let cleaner = TextCleaner()
        let clean = "I think context is even more expensive."
        _ = await cleaner.clean(clean, prompt: CleanupPrompt.standard, vocabulary: [], steps: ["model"], extensions: extensions)
        #expect(calls.count == 0)
        _ = await cleaner.clean(clean, prompt: "Rewrite as a formal email.", vocabulary: [], steps: ["model"], extensions: extensions)
        #expect(calls.count == 1)
    }
}

@MainActor private final class CallCount {
    var count = 0
}

@Suite struct TimeoutTests {
    @Test func cancellingTheCallerStopsTheOperation() async {
        let seen = CancellationSeen()
        let call = Task {
            try await withTimeout(.seconds(5), onTimeout: CleanupError.timedOut) {
                do {
                    try await Task.sleep(for: .seconds(5))
                } catch {
                    await seen.mark()
                }
                return 0
            }
        }
        try? await Task.sleep(for: .milliseconds(50))
        let started = ContinuousClock.now
        call.cancel()
        let result = await call.result
        #expect(ContinuousClock.now - started < .seconds(1))
        #expect(throws: CancellationError.self) { try result.get() }
        for _ in 0..<100 where !(await seen.cancelled) { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(await seen.cancelled)
    }
}

private actor CancellationSeen {
    var cancelled = false

    func mark() {
        cancelled = true
    }
}

@Suite struct CleanupGuardTests {
    @Test func rejectsDroppedNegationsAndChangedTimes() {
        #expect(CleanupGuard.rejection(raw: "I think we should not ship until both are done", cleaned: "I think we should wait until both are done.") == .changedMeaning)
        #expect(CleanupGuard.rejection(raw: "we don't need the report", cleaned: "We need the report.") == .changedMeaning)
        #expect(CleanupGuard.rejection(raw: "der Termin ist am 15. Mai um halb drei", cleaned: "Der Termin ist am 15. Mai um 15:30 Uhr.") == .changedMeaning)
    }
}
