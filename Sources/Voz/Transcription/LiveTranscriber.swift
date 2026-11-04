import FluidAudio
import Foundation

struct AudioChunk: Equatable, Sendable {
    let start: Double
    let samples: [Float]
}

/// Cuts a live stream into chunks at the quietest moment, so a cut rarely splits a word
struct LiveChunker {
    static let shortest = 8.0
    static let longest = 14.0
    private static let frame = Int(RecordingFilter.sampleRate / 10)

    private var pending: [Float] = []
    private var consumed = 0

    var seconds: Double { Double(consumed + pending.count) / RecordingFilter.sampleRate }

    mutating func append(_ samples: [Float]) -> [AudioChunk] {
        pending += samples
        var chunks: [AudioChunk] = []
        while Double(pending.count) / RecordingFilter.sampleRate >= Self.longest {
            chunks.append(take(quietestCut()))
        }
        return chunks
    }

    mutating func flush() -> AudioChunk? {
        pending.isEmpty ? nil : take(pending.count)
    }

    private func quietestCut() -> Int {
        let first = Int(Self.shortest * RecordingFilter.sampleRate)
        let last = Int(Self.longest * RecordingFilter.sampleRate) - Self.frame
        let quietest = stride(from: first, through: last, by: Self.frame).min { energy(at: $0) < energy(at: $1) } ?? last
        return quietest + Self.frame / 2
    }

    private func energy(at start: Int) -> Float {
        pending[start..<start + Self.frame].reduce(0) { $0 + $1 * $1 }
    }

    private mutating func take(_ count: Int) -> AudioChunk {
        let chunk = AudioChunk(start: Double(consumed) / RecordingFilter.sampleRate, samples: Array(pending.prefix(count)))
        pending.removeFirst(count)
        consumed += count
        return chunk
    }
}

/// Holds back words the diarizer hasn't reached yet, so each word gets its speaker once
struct LiveTurns {
    private var numbers: [String: Int] = [:]
    private var waiting: [TimedWord] = []

    mutating func take(_ words: [TimedWord], spans: [SpeakerSpan], diarizedUntil: Double) -> [SpeakerTurn] {
        waiting += words
        let ready = waiting.prefix { $0.end <= diarizedUntil }
        waiting.removeFirst(ready.count)
        return SpeakerTurns.make(words: Array(ready), spans: spans, numbers: &numbers)
    }
}

enum LiveTranscript {
    static func make(_ turns: [SpeakerTurn], seconds: Double) -> FileTranscript {
        var merged: [SpeakerTurn] = []
        for turn in turns {
            if let last = merged.last, last.speaker == turn.speaker {
                merged[merged.count - 1] = SpeakerTurn(speaker: last.speaker, start: last.start, end: turn.end, text: "\(last.text) \(turn.text)", you: last.you)
            } else {
                merged.append(turn)
            }
        }
        return FileTranscript(
            text: merged.map(\.text).joined(separator: " "),
            seconds: seconds,
            speakers: Set(merged.map(\.speaker)).count,
            turns: merged
        )
    }

    /// Puts the user's microphone and the call back in time order. The microphone's turns are speaker 0.
    static func combine(you: FileTranscript, call: FileTranscript) -> FileTranscript {
        let turns = (you.turns + call.turns).sorted { $0.start < $1.start }
        return make(turns, seconds: max(you.seconds, call.seconds))
    }
}

/// Which stream a live transcriber hears. With separate streams, the microphone drops what the speakers played.
enum LiveRole: Sendable {
    case mixed
    case microphone(LiveEcho)
    case system(LiveEcho)
}

/// Transcribes a live stream in chunks and sends the whole transcript so far whenever the diarizer catches up
actor LiveTranscriber {
    // Latency of about 3 seconds keeps turns close to the speech without the cost of the 1-second presets
    private static let diarizerConfig = Nemotron3Config.fast32
    private static let frameSeconds = 0.01

    private let transcriber: Transcriber
    private let model: SpeechModel
    private let vocabulary: VocabularyStore?
    private let role: LiveRole
    private let onTranscript: @Sendable (FileTranscript) async -> Void
    private var diarizer: Nemotron3Diarizer?
    private var chunker = LiveChunker()
    private var turns = LiveTurns()
    private var probabilities: [Float] = []
    private var frames = 0
    private var emitted: [SpeakerTurn] = []

    init(
        transcriber: Transcriber, model: SpeechModel, vocabulary: VocabularyStore?, role: LiveRole = .mixed,
        onTranscript: @escaping @Sendable (FileTranscript) async -> Void
    ) {
        self.transcriber = transcriber
        self.model = model
        self.vocabulary = vocabulary
        self.role = role
        self.onTranscript = onTranscript
    }

    func prepare(speakers: Bool) async throws {
        guard model.modelVersion != nil else { throw FileTranscriberError.needsParakeet }
        try await transcriber.prepare(model)
        guard speakers else { return }
        let models = try await Nemotron3Models.loadFromHuggingFace(config: Self.diarizerConfig, computeUnits: .cpuAndGPU)
        diarizer = Nemotron3Diarizer(config: Self.diarizerConfig, models: models)
    }

    func append(_ samples: [Float]) async throws {
        for chunk in chunker.append(samples) { try await process(chunk, isLast: false) }
    }

    func finish() async throws -> FileTranscript {
        let seconds = chunker.seconds
        try await process(chunker.flush() ?? AudioChunk(start: seconds, samples: []), isLast: true)
        if case .system(let echo) = role { await echo.finish() }
        return LiveTranscript.make(emitted, seconds: seconds)
    }

    private func process(_ chunk: AudioChunk, isLast: Bool) async throws {
        var words = await recognizeOrSkip(chunk)
        switch role {
        case .mixed: break
        case .system(let echo): await echo.heard(words, until: chunk.start + Double(chunk.samples.count) / RecordingFilter.sampleRate)
        case .microphone(let echo): words = await echo.removeEcho(from: words)
        }
        var spans: [SpeakerSpan] = []
        var diarizedUntil = Double.infinity
        if let diarizer {
            diarizer.appendAudio(chunk.samples)
            collect(isLast ? try diarizer.finishStream() : try diarizer.processBufferedAudio())
            spans = Nemotron3Diarizer.segments(probabilities: probabilities, frameCount: frames).map {
                SpeakerSpan(speaker: String($0.speakerIndex), start: Double($0.startSeconds), end: Double($0.endSeconds))
            }
            if !isLast { diarizedUntil = Double(frames) * Self.frameSeconds }
        }
        let rules = vocabulary?.rulesOrLogged() ?? []
        let known = vocabulary?.wordsOrLogged() ?? []
        let ready = turns.take(words, spans: spans, diarizedUntil: diarizedUntil)
        guard !ready.isEmpty else { return }
        emitted += ready.map { turn in
            let fixed = turn.applying(rules, words: known)
            guard case .microphone = role else { return fixed }
            return SpeakerTurn(speaker: 0, start: fixed.start, end: fixed.end, text: fixed.text, you: true)
        }
        await onTranscript(LiveTranscript.make(emitted, seconds: chunker.seconds))
    }

    /// One chunk the model fails on loses those seconds, not the whole meeting
    private func recognizeOrSkip(_ chunk: AudioChunk) async -> [TimedWord] {
        do {
            return try await recognize(chunk)
        } catch {
            Log.extensions.error("Live transcription skipped \(chunk.samples.count / Int(RecordingFilter.sampleRate), privacy: .public) seconds: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func recognize(_ chunk: AudioChunk) async throws -> [TimedWord] {
        guard !chunk.samples.isEmpty else { return [] }
        let result = try await transcriber.recognize(chunk.samples, model: model)
        return buildWordTimings(from: result.tokenTimings ?? []).map {
            TimedWord(text: $0.word, start: chunk.start + $0.startTime, end: chunk.start + $0.endTime)
        }
    }

    private func collect(_ results: [Nemotron3ChunkResult]) {
        for result in results {
            probabilities += result.probabilities
            frames += result.frameCount
        }
    }
}
