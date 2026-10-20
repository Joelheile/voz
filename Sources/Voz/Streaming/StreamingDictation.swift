import Foundation
import VozCore

struct StreamedTranscript {
    let raw: String
    let cleaned: CleanedText
    let sttMs: Int
    let model: SpeechModel
    let audioSeconds: Double
    let segmentCount: Int
    let cleanedInTime: Int
}

enum StreamingError: Error {
    case segmentTranscriptionFailed
}

@MainActor
private final class Segment {
    let transcription: Task<TranscriptionResult?, Never>
    var cleanup: Task<Void, Never>?
    var cleaned: CleanedText?

    init(transcription: Task<TranscriptionResult?, Never>) {
        self.transcription = transcription
    }
}

@MainActor
final class StreamingDictation {
    private let engine: SpeechEngine
    private let cleaner: TextCleaner
    private let model: SpeechModel
    private let vocabulary: [String]
    private let prompt: Task<String, Never>
    private let cleanupEnabled: Bool
    private var detector = PauseDetector()
    private var pendingAudio: [Float] = []
    private var committedSamples = 0
    private var segments: [Segment] = []
    private var releaseDeadline: ContinuousClock.Instant?
    private var closed = false

    init(engine: SpeechEngine, cleaner: TextCleaner, model: SpeechModel, vocabulary: [String], prompt: Task<String, Never>, cleanupEnabled: Bool) {
        self.engine = engine
        self.cleaner = cleaner
        self.model = model
        self.vocabulary = vocabulary
        self.prompt = prompt
        self.cleanupEnabled = cleanupEnabled
    }

    func feed(_ samples: [Float]) {
        guard !closed else { return }
        pendingAudio.append(contentsOf: samples)
        for cut in detector.append(samples) {
            let length = cut - committedSamples
            guard length > 0, length <= pendingAudio.count else { continue }
            let audio = Array(pendingAudio.prefix(length))
            pendingAudio.removeFirst(length)
            committedSamples = cut
            segments.append(makeSegment(audio))
            Log.app.notice("Committed segment \(self.segments.count) at \(Double(cut) / RecordingFilter.sampleRate, format: .fixed(precision: 1))s")
        }
    }

    func cancel() {
        closed = true
        for segment in segments {
            segment.transcription.cancel()
            segment.cleanup?.cancel()
        }
        segments = []
    }

    func finish(samples: [Float], released: ContinuousClock.Instant) async throws -> StreamedTranscript? {
        closed = true
        let deadline = released + CleanupBudget.total
        releaseDeadline = deadline
        let tailStart = min(committedSamples, samples.count)
        let tailAudio = Array(samples[tailStart...])
        let keepsTail = segments.isEmpty || RecordingFilter.verdict(for: tailAudio) == .keep
        let tail = keepsTail ? makeSegment(tailAudio) : nil
        if let tail { segments.append(tail) }

        let tailResult = await tail?.transcription.value
        let transcribedAt = ContinuousClock.now
        var results: [TranscriptionResult] = []
        for segment in segments {
            guard let result = await segment.transcription.value else { throw StreamingError.segmentTranscriptionFailed }
            results.append(result)
        }
        if let last = segments.last?.cleanup { await wait(for: last, until: deadline) }
        let cleanupWait = ContinuousClock.now - transcribedAt

        let raws = results.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard raws.contains(where: { !$0.isEmpty }) else { return nil }
        return assemble(raws: raws, results: results, tailResult: tailResult, samples: samples, cleanupWait: cleanupWait)
    }

    private func assemble(raws: [String], results: [TranscriptionResult], tailResult: TranscriptionResult?, samples: [Float], cleanupWait: Duration) -> StreamedTranscript {
        var cleanedTexts: [String?] = []
        var fallbacks: [String] = []
        var fillersRemoved = 0
        var timedOut = false
        var cleanedInTime = 0
        for (segment, raw) in zip(segments, raws) {
            let rules = cleanupEnabled ? cleaner.ruleText(raw, vocabulary: vocabulary) : FillerPassResult(text: raw, removed: 0)
            fallbacks.append(rules.text)
            cleanedTexts.append(segment.cleaned?.text)
            guard !raw.isEmpty else { continue }
            if let cleaned = segment.cleaned {
                cleanedInTime += 1
                fillersRemoved += cleaned.fillerWordsRemoved
                timedOut = timedOut || cleaned.timedOut
            } else {
                fillersRemoved += rules.removed
                timedOut = true
            }
        }
        let cleaned = CleanedText(
            text: SegmentJoiner.join(cleaned: cleanedTexts, fallback: fallbacks),
            fillerWordsRemoved: fillersRemoved,
            milliseconds: cleanupWait.wholeMilliseconds,
            timedOut: timedOut,
            rejection: segments.compactMap { $0.cleaned?.rejection }.first
        )
        return StreamedTranscript(
            raw: SegmentJoiner.join(raws),
            cleaned: cleaned,
            sttMs: Int((tailResult?.processingSeconds ?? 0) * 1000),
            model: results[results.count - 1].model,
            audioSeconds: Double(samples.count) / RecordingFilter.sampleRate,
            segmentCount: raws.filter { !$0.isEmpty }.count,
            cleanedInTime: cleanedInTime
        )
    }

    private func makeSegment(_ audio: [Float]) -> Segment {
        let engine = engine
        let model = model
        let vocabulary = vocabulary
        let transcription = Task { () -> TranscriptionResult? in
            do {
                return try await engine.transcribe(audio, model: model, vocabulary: vocabulary)
            } catch {
                Log.app.error("Segment transcription failed: \(error.localizedDescription, privacy: .private)")
                return nil
            }
        }
        let segment = Segment(transcription: transcription)
        let previous = segments.last?.cleanup
        segment.cleanup = Task {
            await previous?.value
            guard let result = await transcription.value else { return }
            let raw = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty, !Task.isCancelled else { return }
            segment.cleaned = await clean(raw)
        }
        return segment
    }

    private func clean(_ raw: String) async -> CleanedText {
        guard cleanupEnabled else {
            return CleanedText(text: raw, fillerWordsRemoved: 0, milliseconds: 0, timedOut: false, rejection: nil)
        }
        let deadline = releaseDeadline ?? ContinuousClock.now + CleanupBudget.segmentTimeout
        return await cleaner.clean(raw, prompt: await prompt.value, vocabulary: vocabulary, deadline: deadline)
    }

    private func wait(for task: Task<Void, Never>, until deadline: ContinuousClock.Instant) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await task.value }
            group.addTask { try? await Task.sleep(until: deadline, clock: .continuous) }
            await group.next()
            group.cancelAll()
        }
    }
}
