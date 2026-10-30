import AVFoundation
import FluidAudio
import UniformTypeIdentifiers

struct TimedWord: Equatable, Sendable {
    let text: String
    let start: Double
    let end: Double
}

struct SpeakerSpan: Equatable, Sendable {
    let speaker: String
    let start: Double
    let end: Double
}

struct SpeakerTurn: Codable, Equatable, Sendable {
    let speaker: Int
    let start: Double
    let end: Double
    let text: String
}

struct FileTranscript: Codable, Equatable, Sendable {
    let text: String
    let seconds: Double
    let speakers: Int
    let turns: [SpeakerTurn]

    func applying(_ rules: [VocabularyRule], words: [String]) -> FileTranscript {
        let fix = { VocabularyCasing.apply(words, to: VocabularyRule.apply(rules, to: $0)) }
        return FileTranscript(
            text: fix(text),
            seconds: seconds,
            speakers: speakers,
            turns: turns.map { SpeakerTurn(speaker: $0.speaker, start: $0.start, end: $0.end, text: fix($0.text)) }
        )
    }
}

enum SpeakerTurns {
    static func make(words: [TimedWord], spans: [SpeakerSpan]) -> [SpeakerTurn] {
        var numbers: [String: Int] = [:]
        var turns: [SpeakerTurn] = []
        for word in words {
            let label = speaker(of: word, in: spans)
            let number = numbers[label] ?? numbers.count + 1
            numbers[label] = number
            if let last = turns.last, last.speaker == number {
                turns[turns.count - 1] = SpeakerTurn(speaker: number, start: last.start, end: word.end, text: "\(last.text) \(word.text)")
            } else {
                turns.append(SpeakerTurn(speaker: number, start: word.start, end: word.end, text: word.text))
            }
        }
        return turns
    }

    private static func speaker(of word: TimedWord, in spans: [SpeakerSpan]) -> String {
        let middle = (word.start + word.end) / 2
        let nearest = spans.min { distance(from: middle, to: $0) < distance(from: middle, to: $1) }
        return nearest?.speaker ?? ""
    }

    private static func distance(from time: Double, to span: SpeakerSpan) -> Double {
        max(span.start - time, time - span.end, 0)
    }
}

enum MediaFile {
    private static let readable = Set(AVURLAsset.audiovisualTypes())
    private static let transportStreamSyncByte: UInt8 = 0x47

    static func isSupported(_ file: URL) -> Bool {
        guard file.isFileURL, let type = UTType(filenameExtension: file.pathExtension) else { return false }
        let isAudioOrVideo = type.conforms(to: .audio) || type.conforms(to: .movie)
        guard isAudioOrVideo, readable.contains(AVFileType(rawValue: type.identifier)) else { return false }
        return !type.conforms(to: .mpeg2TransportStream) || startsWithTransportStreamPacket(file)
    }

    // MPEG-TS packets start with the sync byte; AVCHD packets put a 4-byte timestamp before it
    private static func startsWithTransportStreamPacket(_ file: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return false }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 5) else { return false }
        return header.first == transportStreamSyncByte || (header.count == 5 && header.last == transportStreamSyncByte)
    }
}

enum FileTranscriberError: Error, LocalizedError {
    case needsParakeet
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .needsParakeet: "Transcribing files needs a Parakeet speech model. Pick one in Settings"
        case .unsupported(let name): "Voz can't read \(name). Use an audio file, MP4 or MOV"
        }
    }
}

struct FileTranscriber: Sendable {
    let transcriber: Transcriber
    let vocabulary: VocabularyStore?

    func transcribe(_ url: URL, model: SpeechModel, speakers: Bool) async throws -> FileTranscript {
        guard MediaFile.isSupported(url) else { throw FileTranscriberError.unsupported(url.lastPathComponent) }
        guard model.modelVersion != nil else { throw FileTranscriberError.needsParakeet }
        let result = try await transcriber.recognize(url, model: model)
        let words = buildWordTimings(from: result.tokenTimings ?? []).map {
            TimedWord(text: $0.word, start: $0.startTime, end: $0.endTime)
        }
        let spans = speakers ? try await Self.speakerSpans(in: url) : []
        let turns = SpeakerTurns.make(words: words, spans: spans)
        return FileTranscript(
            text: result.text,
            seconds: result.duration,
            speakers: Set(turns.map(\.speaker)).count,
            turns: turns
        ).applying((try? vocabulary?.rules()) ?? [], words: (try? vocabulary?.words()) ?? [])
    }

    private static let diarizerConfig = Nemotron3Config(
        chunkLen: 128, chunkRightContext: 4, fifoLen: 40, spkcacheUpdatePeriod: 40,
        modelFileName: "Nemotron3Diarizer_c128_split_w8a8.mlmodelc", splitGraph: true
    )

    private static func speakerSpans(in url: URL) async throws -> [SpeakerSpan] {
        let models = try await Nemotron3Models.loadFromHuggingFace(config: diarizerConfig)
        let samples = try AudioConverter().resampleAudioFile(url)
        let (probabilities, frames) = try Nemotron3Diarizer(config: diarizerConfig, models: models).processComplete(samples)
        return Nemotron3Diarizer.segments(probabilities: probabilities, frameCount: frames).map {
            SpeakerSpan(speaker: String($0.speakerIndex), start: Double($0.startSeconds), end: Double($0.endSeconds))
        }
    }
}
