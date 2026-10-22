import Testing
@testable import Voz

@Suite @MainActor struct StreamingTests {
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
}
