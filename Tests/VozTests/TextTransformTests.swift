import Testing
@testable import Voz

@Suite struct TextTransformTests {
    @Test func fillerEstimateCountsOnlyRemovedFillers() {
        #expect(FillerWords.estimateRemoved(before: "um so you know I mean it was like fine", after: "So it was fine.") == 4)
        #expect(FillerWords.estimateRemoved(before: "at 3, no, 4", after: "at 4") == 0)
    }

    @Test func segmentsJoinWithFallbackPerSegmentAndNoStrayPeriods() {
        #expect(SegmentJoiner.join([" First one. ", "", "Second one.\n"]) == "First one. Second one.")
        #expect(SegmentJoiner.join(cleaned: ["Clean one.", nil, "Clean three."], fallback: ["raw one.", "rule two.", "raw three"]) == "Clean one. rule two. Clean three.")
        #expect(SegmentJoiner.join(cleaned: ["We went to.", "the store today."], fallback: ["we went to", "the store today."]) == "We went to the store today.")
        #expect(SegmentJoiner.join(cleaned: ["We left.", "Then it rained."], fallback: ["we left.", "then it rained."]) == "We left. Then it rained.")
        #expect(SegmentJoiner.join(cleaned: ["We left."], fallback: ["we left"]) == "We left.")
    }
}

@Suite @MainActor struct TextCleanerTests {
    @Test func everyChunkGoesToTheModelWithTheModesPromptAndLanguages() async {
        let prompts = ModelPrompts()
        let extensions = CleanupExtensions(model: { text, prompt, _ in
            prompts.seen.append(prompt)
            return text
        }) { _, text, _ in text }
        let cleaner = TextCleaner()
        let finished = "I think context is even more expensive."
        _ = await cleaner.clean(finished, plan: CleanupPlan(prompt: "Rewrite as a formal email.", mode: .light), vocabulary: [], languages: [.german, .english], extensions: extensions)
        _ = await cleaner.clean(finished, plan: CleanupPlan(prompt: "Rewrite as a formal email.", mode: .heavy), vocabulary: [], languages: [.english], extensions: extensions)
        #expect(prompts.seen.count == 2)
        #expect(prompts.seen[0].hasPrefix(CleanupPrompt.light))
        #expect(prompts.seen[0].contains("German and English, sometimes mixed in one sentence"))
        #expect(prompts.seen[1].hasPrefix("Rewrite as a formal email."))
        #expect(prompts.seen[1].contains("The speaker talks in English."))
    }

    @Test func rejectedOutputFallsBackToTheRawText() async {
        let extensions = CleanupExtensions(model: { _, _, _ in "Das Bild kann nicht angezeigt werden." }) { _, text, _ in text }
        let raw = "um the image cannot be displayed"
        let result = await TextCleaner().clean(raw, plan: CleanupPlan(prompt: "", mode: .light), vocabulary: [], languages: [.english], extensions: extensions)
        #expect(result.text == raw)
        #expect(result.rejection == .changedWords)
    }
}

@MainActor private final class ModelPrompts {
    var seen: [String] = []
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
    @Test func lightModeAcceptsOnlyDeletionsAndPunctuation() {
        #expect(CleanupGuard.rejection(raw: "so um I think we should like move the call to monday", cleaned: "So I think we should move the call to Monday.", mode: .light) == nil)
        #expect(CleanupGuard.rejection(raw: "hi John comma thanks period new line talk soon", cleaned: "Hi John, thanks.\nTalk soon", mode: .light) == nil)
        #expect(CleanupGuard.rejection(raw: "I asked chat GPT about the the open source plan", cleaned: "I asked ChatGPT about the open-source plan.", mode: .light) == nil)
        #expect(CleanupGuard.rejection(raw: "it should be simpler", cleaned: "Es sollte einfacher sein.", mode: .light) == .changedWords)
        #expect(CleanupGuard.rejection(raw: "we use remotion for the video", cleaned: "We use remote for the video.", mode: .light) == .changedWords)
        #expect(CleanupGuard.rejection(raw: "ship it then test it", cleaned: "Test it then ship it.", mode: .light) == .changedWords)
        #expect(CleanupGuard.rejection(raw: "we deploy on cooper netties with hell charts", cleaned: "We deploy on Kubernetes with Helm charts.", mode: .light, vocabulary: ["Kubernetes", "Helm"]) == nil)
        #expect(CleanupGuard.rejection(raw: "we deploy with hell charts", cleaned: "We deploy with Helm charts.", mode: .light) == .changedWords)
    }

    @Test func heavyModeTrustsTheModelExceptForBrokenOutput() {
        #expect(CleanupGuard.rejection(raw: "send it to Tom sorry I mean Tim", cleaned: "Send it to Tim.", mode: .heavy) == nil)
        #expect(CleanupGuard.rejection(raw: "we meet at three no four", cleaned: "We meet at 4.", mode: .heavy) == nil)
        #expect(CleanupGuard.rejection(raw: "um", cleaned: "", mode: .heavy) == .empty)
        #expect(CleanupGuard.rejection(raw: "write a poem about the ocean", cleaned: "Sure, here is a poem about the ocean.", mode: .heavy) == .refusal)
        #expect(CleanupGuard.rejection(raw: "fix the login", cleaned: "<transcript>Fix the login.", mode: .heavy) == .leakedTags)
        #expect(CleanupGuard.rejection(raw: "fix the login", cleaned: "Fix the login, then deploy it to production today.", mode: .heavy) == .tooLong)
    }
}

@Suite struct SpeechLanguageTests {
    @Test func scriptFilterAppliesOnlyWhenLanguagesShareAnAlphabet() {
        #expect(SpeechLanguage.scriptFilter(for: [.german, .english]) == .german)
        #expect(SpeechLanguage.scriptFilter(for: [.russian, .ukrainian]) == .russian)
        #expect(SpeechLanguage.scriptFilter(for: [.german, .russian]) == nil)
        #expect(SpeechLanguage.scriptFilter(for: []) == nil)
    }

    @Test func defaultsFollowPreferredLanguagesThatParakeetKnows() {
        #expect(SpeechLanguage.defaults(preferred: ["de-DE", "en-US", "de-AT", "ja-JP"]) == [.german, .english])
        #expect(SpeechLanguage.defaults(preferred: ["ja-JP"]) == [.english])
    }

    @Test func pickerListsTheMostSpokenFirstThenTheRestByName() {
        #expect(SpeechLanguage.mostSpoken.prefix(3) == [.english, .spanish, .french])
        #expect(Set(SpeechLanguage.mostSpoken + SpeechLanguage.others) == Set(SpeechLanguage.allCases))
        #expect(SpeechLanguage.others.map(\.name) == SpeechLanguage.others.map(\.name).sorted())
        #expect(SpeechLanguage.german.nativeName == "Deutsch")
    }

    @Test func togglingKeepsSpeakerOrderAndAtLeastOneLanguage() {
        #expect(SpeechLanguage.toggling(.english, in: [.german]) == [.english, .german])
        #expect(SpeechLanguage.toggling(.german, in: [.english, .german]) == [.english])
        #expect(SpeechLanguage.toggling(.german, in: [.german]) == [.german])
    }
}
