import Testing
@testable import Voz

@Suite(.serialized) @MainActor struct StreamingTests {
    @Test func finishHonorsReleaseDeadlineWhenCleanupIgnoresCancellation() async throws {
        let cleaner = TextCleaner()
        let started = ContinuousClock.now
        let extensions = CleanupExtensions(model: nil) { _, text, _ in
            // Simulate external work that does not cooperate with task cancellation.
            await withCheckedContinuation { continuation in
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    continuation.resume(returning: text)
                }
            }
        }
        let stream = StreamingDictation(
            transcribe: { _ in TranscriptionResult(text: "um keep these words", audioSeconds: 1, processingSeconds: 0, model: "test") },
            cleaner: cleaner, vocabulary: [], prompt: Task { "" }, cleanupEnabled: true,
            steps: ["fillers", "slow"], extensions: extensions
        )
        let result = try #require(await stream.finish(samples: [0.5], released: started))
        #expect(ContinuousClock.now - started < .seconds(2.5))
        #expect(result.cleaned.text == "Keep these words")
        #expect(result.cleaned.timedOut)
        stream.cancel()
    }

    @Test func cleansWholeSentencesAcrossPausesEvenWhenAPauseGetsAPeriod() async throws {
        let speech = Int(RecordingFilter.sampleRate * 2.5)
        let pause = Int(RecordingFilter.sampleRate * 0.7)
        let first = [Float](repeating: 0.5, count: speech) + [Float](repeating: 0, count: pause)
        let second = [Float](repeating: 0.5, count: speech * 2) + [Float](repeating: 0, count: pause)
        let fragment = { (audio: [Float]) in audio.count < speech * 2 ? "so uh I think we should." : "uh move the call to monday" }
        let modelInputs = ModelInputs()
        let extensions = CleanupExtensions(model: { text, _, _ in
            modelInputs.texts.append(text)
            return text
        }) { _, text, _ in text }
        let stream = StreamingDictation(
            transcribe: { TranscriptionResult(text: fragment($0), audioSeconds: 1, processingSeconds: 0, model: "test") },
            cleaner: TextCleaner(), vocabulary: [], prompt: Task { "" }, cleanupEnabled: true,
            steps: ["fillers", "model"], extensions: extensions
        )
        stream.feed(first)
        stream.feed(second)
        let result = try #require(await stream.finish(samples: first + second, released: .now))
        #expect(modelInputs.texts.first == "So I think we should. move the call to monday")
        #expect(result.cleaned.text == "So I think we should. move the call to monday")
    }
}

@MainActor private final class ModelInputs {
    var texts: [String] = []
}
