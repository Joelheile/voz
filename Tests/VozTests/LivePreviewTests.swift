import Testing
@testable import Voz

@Suite(.serialized) @MainActor struct LivePreviewTests {
    @Test func previewsSpeechBeforeReleaseWithoutWaitingForCleanup() async throws {
        var previews: [String] = []
        var finishCleanup: CheckedContinuation<String, Never>?
        let extensions = CleanupExtensions(model: { _, _, _ in
            await withCheckedContinuation { finishCleanup = $0 }
        }) { _, text, _ in text }
        let stream = StreamingDictation(
            transcribe: { _ in TranscriptionResult(text: "First sentence. Still talking", audioSeconds: 1, processingSeconds: 0, model: "test") },
            cleaner: TextCleaner(), vocabulary: [], plan: Task { CleanupPlan(prompt: "", mode: .heavy) }, cleanupEnabled: true,
            steps: ["model"], extensions: extensions
        )
        stream.onPreview = { previews.append($0) }
        defer { stream.cancel(); finishCleanup?.resume(returning: "First sentence.") }
        stream.feed(speechWithPause())
        for _ in 0..<100 where previews.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        #expect(previews == ["First sentence. Still talking"])
    }

    @Test func previewsStayInAudioOrderWhenTranscriptionsFinishOutOfOrder() async throws {
        var previews: [String] = []
        var calls = 0
        let stream = StreamingDictation(
            transcribe: { _ in
                calls += 1
                let first = calls == 1
                if first { try await Task.sleep(for: .milliseconds(60)) }
                return TranscriptionResult(text: first ? "First" : "second", audioSeconds: 1, processingSeconds: 0, model: "test")
            },
            cleaner: TextCleaner(), vocabulary: [], plan: Task { CleanupPlan(prompt: "", mode: .heavy) }, cleanupEnabled: false
        )
        stream.onPreview = { previews.append($0) }
        defer { stream.cancel() }
        stream.feed(speechWithPause())
        stream.feed(speechWithPause())
        for _ in 0..<100 where previews.last != "First second" { try await Task.sleep(for: .milliseconds(5)) }
        #expect(previews.last == "First second")
        #expect(!previews.contains("second"))
    }

    @Test func cancelledRecordingCannotPublishLatePreview() async throws {
        var previews: [String] = []
        var finishTranscription: CheckedContinuation<TranscriptionResult, Never>?
        let stream = StreamingDictation(
            transcribe: { _ in await withCheckedContinuation { finishTranscription = $0 } },
            cleaner: TextCleaner(), vocabulary: [], plan: Task { CleanupPlan(prompt: "", mode: .heavy) }, cleanupEnabled: false
        )
        stream.onPreview = { previews.append($0) }
        stream.feed(speechWithPause())
        for _ in 0..<100 where finishTranscription == nil { try await Task.sleep(for: .milliseconds(5)) }
        stream.cancel()
        let continuation = try #require(finishTranscription)
        continuation.resume(returning: TranscriptionResult(text: "Stale words", audioSeconds: 1, processingSeconds: 0, model: "test"))
        try await Task.sleep(for: .milliseconds(30))
        #expect(previews.isEmpty)
    }

    @Test func finalPreviewUsesCleanedTextIncludingTheTail() async throws {
        var previews: [String] = []
        let stream = StreamingDictation(
            transcribe: { _ in TranscriptionResult(text: "um ship it", audioSeconds: 1, processingSeconds: 0, model: "test") },
            cleaner: TextCleaner(), vocabulary: [], plan: Task { CleanupPlan(prompt: "", mode: .heavy) }, cleanupEnabled: true, steps: ["fillers"]
        )
        stream.onPreview = { previews.append($0) }
        let result = try #require(await stream.finish(samples: [0.5], released: .now))
        #expect(previews.last == result.cleaned.text)
        #expect(previews.last == "Ship it")
    }

    @Test func previewsWordsWhileSpeakingBeforeAnyPause() async throws {
        var previews: [String] = []
        let stream = StreamingDictation(
            transcribe: { _ in TranscriptionResult(text: "Still talking", audioSeconds: 1, processingSeconds: 0, model: "test") },
            cleaner: TextCleaner(), vocabulary: [], plan: Task { CleanupPlan(prompt: "", mode: .heavy) }, cleanupEnabled: false
        )
        stream.onPreview = { previews.append($0) }
        defer { stream.cancel() }
        stream.feed([Float](repeating: 0.5, count: Int(RecordingFilter.sampleRate * 1)))
        for _ in 0..<100 where previews.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        #expect(previews == ["Still talking"])
    }

    @Test func committedSegmentReplacesTheInterimWordsItCovers() async throws {
        var previews: [String] = []
        var calls = 0
        let stream = StreamingDictation(
            transcribe: { _ in
                calls += 1
                return TranscriptionResult(text: calls == 1 ? "First draft" : "First sentence.", audioSeconds: 1, processingSeconds: 0, model: "test")
            },
            cleaner: TextCleaner(), vocabulary: [], plan: Task { CleanupPlan(prompt: "", mode: .heavy) }, cleanupEnabled: false
        )
        stream.onPreview = { previews.append($0) }
        defer { stream.cancel() }
        stream.feed([Float](repeating: 0.5, count: Int(RecordingFilter.sampleRate * 1)))
        for _ in 0..<100 where previews.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        stream.feed(speechWithPause())
        for _ in 0..<100 where previews.last != "First sentence." { try await Task.sleep(for: .milliseconds(5)) }
        #expect(previews == ["First draft", "First sentence."])
    }

    private func speechWithPause() -> [Float] {
        [Float](repeating: 0.5, count: Int(RecordingFilter.sampleRate * 2.5))
            + [Float](repeating: 0, count: Int(RecordingFilter.sampleRate * 0.7))
    }
}
