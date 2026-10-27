import Foundation

struct StreamedTranscript {
    let raw: String
    let cleaned: CleanedText
    let sttMs: Int
    let model: String
    let audioSeconds: Double
    let segmentCount: Int
    let unitCount: Int
    let cleanedInTime: Int
}

enum StreamingError: Error {
    case segmentTranscriptionFailed
}

@MainActor
private final class Segment {
    let transcription: Task<TranscriptionResult?, Never>
    var collection: Task<Void, Never>?

    init(transcription: Task<TranscriptionResult?, Never>) {
        self.transcription = transcription
    }
}

@MainActor
private final class CleanupUnit {
    let raw: String
    var cleaned: CleanedText?

    init(raw: String) {
        self.raw = raw
    }
}

@MainActor
private final class Speculation {
    let raw: String
    let result: Task<CleanedText, Never>

    init(raw: String, result: Task<CleanedText, Never>) {
        self.raw = raw
        self.result = result
    }
}

typealias SegmentTranscriber = @MainActor ([Float]) async throws -> TranscriptionResult

@MainActor
final class StreamingDictation {
    static let maximumOpenWords = 25

    private let transcribe: SegmentTranscriber
    private let cleaner: TextCleaner
    private let vocabulary: [String]
    private let prompt: Task<String, Never>
    private let cleanupEnabled: Bool
    private let steps: [String]
    private let extensions: CleanupExtensions
    private var detector = PauseDetector()
    private var pendingAudio: [Float] = []
    private var committedSamples = 0
    private var segments: [Segment] = []
    private var units: [CleanupUnit] = []
    private var openText = ""
    private var collectedSegments = 0
    private var speculation: Speculation?
    private var releaseDeadline: ContinuousClock.Instant?
    private var closed = false
    private var previewSegments: [String?] = []
    var onPreview: ((String) -> Void)?

    init(
        transcribe: @escaping SegmentTranscriber,
        cleaner: TextCleaner,
        vocabulary: [String],
        prompt: Task<String, Never>,
        cleanupEnabled: Bool,
        steps: [String] = CleanupStep.standard,
        extensions: CleanupExtensions = .none
    ) {
        self.transcribe = transcribe
        self.cleaner = cleaner
        self.vocabulary = vocabulary
        self.prompt = prompt
        self.cleanupEnabled = cleanupEnabled
        self.steps = steps
        self.extensions = extensions
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
        onPreview = nil
        prompt.cancel()
        for segment in segments {
            segment.transcription.cancel()
            segment.collection?.cancel()
        }
        segments = []
        speculation?.result.cancel()
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
        let previous = segments.last?.collection
        let rest = Task {
            await previous?.value
            guard let unit = closeOpenText() else { return }
            if let speculation, speculation.raw == unit.raw {
                unit.cleaned = await speculation.result.value
            } else {
                await cleanUp(unit)
            }
        }
        await wait(for: rest, until: deadline)
        rest.cancel()
        for segment in segments { segment.collection?.cancel() }
        speculation?.result.cancel()
        prompt.cancel()
        let cleanupWait = ContinuousClock.now - transcribedAt

        let raws = results.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard raws.contains(where: { !$0.isEmpty }) else { return nil }
        let transcript = assemble(raws: raws, results: results, tailResult: tailResult, samples: samples, cleanupWait: cleanupWait)
        onPreview?(transcript.cleaned.text)
        onPreview = nil
        return transcript
    }

    private func assemble(raws: [String], results: [TranscriptionResult], tailResult: TranscriptionResult?, samples: [Float], cleanupWait: Duration) -> StreamedTranscript {
        let uncollected = SegmentJoiner.join([openText] + raws.dropFirst(collectedSegments))
        let pieces = units + (uncollected.isEmpty ? [] : [CleanupUnit(raw: uncollected)])
        var cleanedTexts: [String?] = []
        var fallbacks: [String] = []
        var fillersRemoved = 0
        var timedOut = false
        var cleanedInTime = 0
        for piece in pieces {
            let rules = cleanupEnabled ? CleanupStep.applyRules(steps, to: piece.raw, vocabulary: vocabulary) : RulePassResult(text: piece.raw, removed: 0)
            fallbacks.append(rules.text)
            cleanedTexts.append(piece.cleaned?.text)
            if let cleaned = piece.cleaned {
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
            rejection: pieces.compactMap { $0.cleaned?.rejection }.first
        )
        return StreamedTranscript(
            raw: SegmentJoiner.join(raws),
            cleaned: cleaned,
            sttMs: Int((tailResult?.processingSeconds ?? 0) * 1000),
            model: results[results.count - 1].model,
            audioSeconds: Double(samples.count) / RecordingFilter.sampleRate,
            segmentCount: raws.filter { !$0.isEmpty }.count,
            unitCount: pieces.count,
            cleanedInTime: cleanedInTime
        )
    }

    private func makeSegment(_ audio: [Float]) -> Segment {
        let transcribe = transcribe
        let index = previewSegments.count
        previewSegments.append(nil)
        let transcription = Task { () -> TranscriptionResult? in
            do {
                let result = try await transcribe(audio)
                guard !Task.isCancelled else { return nil }
                previewSegments[index] = result.text
                let available = previewSegments.prefix { $0 != nil }.compactMap { $0 }
                let text = SegmentJoiner.join(available)
                if !text.isEmpty { onPreview?(text) }
                return result
            } catch {
                Log.app.error("Segment transcription failed: \(error.localizedDescription, privacy: .private)")
                Analytics.report(.segmentTranscriptionFailed)
                return nil
            }
        }
        let segment = Segment(transcription: transcription)
        let previous = segments.last?.collection
        segment.collection = Task {
            await previous?.value
            guard let result = await transcription.value else { return }
            if let unit = collect(result.text) { await cleanUp(unit) }
            speculate()
        }
        return segment
    }

    private func collect(_ text: String) -> CleanupUnit? {
        collectedSegments += 1
        defer { dropStaleSpeculation() }
        let split = SentenceChunks.splitLastSentence(text)
        guard !split.before.isEmpty else {
            openText = SegmentJoiner.join([openText, text])
            let isLong = openText.split(whereSeparator: \.isWhitespace).count >= Self.maximumOpenWords
            return isLong ? closeOpenText() : nil
        }
        let settled = SegmentJoiner.join([openText, split.before])
        openText = split.last.trimmingCharacters(in: .whitespacesAndNewlines)
        return addUnit(settled)
    }

    private func dropStaleSpeculation() {
        guard let speculation, speculation.raw != openText else { return }
        speculation.result.cancel()
        self.speculation = nil
    }

    private func speculate() {
        guard speculation == nil, !openText.isEmpty, !Task.isCancelled else { return }
        let raw = openText
        speculation = Speculation(raw: raw, result: Task { await clean(raw) })
    }

    private func closeOpenText() -> CleanupUnit? {
        guard !openText.isEmpty else { return nil }
        defer { openText = "" }
        return addUnit(openText)
    }

    private func addUnit(_ raw: String) -> CleanupUnit {
        let unit = CleanupUnit(raw: raw)
        units.append(unit)
        return unit
    }

    private func cleanUp(_ unit: CleanupUnit) async {
        guard !Task.isCancelled else { return }
        unit.cleaned = await clean(unit.raw)
    }

    private func clean(_ raw: String) async -> CleanedText {
        guard cleanupEnabled else {
            return CleanedText(text: raw, fillerWordsRemoved: 0, milliseconds: 0, timedOut: false, rejection: nil)
        }
        let deadline = releaseDeadline ?? ContinuousClock.now + CleanupBudget.segmentTimeout
        return await cleaner.clean(raw, prompt: await prompt.value, vocabulary: vocabulary, steps: steps, extensions: extensions, deadline: deadline)
    }

    private func wait(for task: Task<Void, Never>, until deadline: ContinuousClock.Instant) async {
        guard deadline > .now else { return }
        do {
            try await withTimeout(deadline - .now, onTimeout: CleanupError.timedOut) {
                await task.value
            }
        } catch CleanupError.timedOut {
            task.cancel()
        } catch {
            Log.app.error("Waiting for cleanup failed: \(error.localizedDescription, privacy: .private)")
        }
    }
}
