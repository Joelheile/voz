import AVFoundation
import FluidAudio
import Synchronization
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

    static func samples(of file: URL) async throws -> [Float] {
        let asset = AVURLAsset(url: file)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw FileTranscriberError.unsupported(file.lastPathComponent)
        }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: RecordingFilter.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ])
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? FileTranscriberError.unsupported(file.lastPathComponent) }
        var samples: [Float] = []
        while let buffer = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(buffer) {
            try Task.checkCancellation()
            let bytes = CMBlockBufferGetDataLength(block)
            let start = samples.count
            samples += repeatElement(0, count: bytes / MemoryLayout<Float>.size)
            let status = samples.withUnsafeMutableBytes { raw in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: bytes, destination: raw.baseAddress! + start * MemoryLayout<Float>.size)
            }
            guard status == kCMBlockBufferNoErr else { throw FileTranscriberError.unsupported(file.lastPathComponent) }
        }
        if reader.status == .failed { throw reader.error ?? FileTranscriberError.unsupported(file.lastPathComponent) }
        return samples
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
    let diarizer = SpeakerDiarizer()

    func transcribe(
        _ url: URL,
        model: SpeechModel,
        speakers: Bool,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> FileTranscript {
        guard MediaFile.isSupported(url) else { throw FileTranscriberError.unsupported(url.lastPathComponent) }
        guard model.modelVersion != nil else { throw FileTranscriberError.needsParakeet }
        let samples = try await MediaFile.samples(of: url)
        let meter = ProgressMeter(parts: speakers ? 2 : 1, report: progress)
        async let recognized = transcriber.recognize(samples, model: model) { meter.update(part: 0, to: $0) }
        async let spans = speakers ? diarizer.spans(in: samples) { meter.update(part: 1, to: $0) } : []
        let result = try await recognized
        let words = buildWordTimings(from: result.tokenTimings ?? []).map {
            TimedWord(text: $0.word, start: $0.startTime, end: $0.endTime)
        }
        let turns = SpeakerTurns.make(words: words, spans: try await spans)
        return FileTranscript(
            text: result.text,
            seconds: result.duration,
            speakers: Set(turns.map(\.speaker)).count,
            turns: turns
        ).applying(vocabulary?.rulesOrLogged() ?? [], words: vocabulary?.wordsOrLogged() ?? [])
    }
}

// Reports the mean of parts that run in parallel, so the total only moves forward
final class ProgressMeter: Sendable {
    private let fractions: Mutex<[Double]>
    private let report: @Sendable (Double) -> Void

    init(parts: Int, report: @escaping @Sendable (Double) -> Void) {
        fractions = Mutex(Array(repeating: 0, count: parts))
        self.report = report
    }

    func update(part: Int, to fraction: Double) {
        let total = fractions.withLock { fractions in
            fractions[part] = max(fractions[part], min(fraction, 1))
            return fractions.reduce(0, +) / Double(fractions.count)
        }
        report(total)
    }
}

actor SpeakerDiarizer {
    private static let config = Nemotron3Config.offline
    private static let blockSamples = 30 * Int(RecordingFilter.sampleRate)
    private var models: Nemotron3Models?

    // Runs on the GPU so it doesn't wait for the Neural Engine, which Parakeet uses at the same time
    private func loadedModels() async throws -> Nemotron3Models {
        if let models { return models }
        let loaded = try await Nemotron3Models.loadFromHuggingFace(config: Self.config, computeUnits: .cpuAndGPU)
        models = loaded
        return loaded
    }

    func spans(in samples: [Float], progress: @Sendable (Double) -> Void) async throws -> [SpeakerSpan] {
        let diarizer = Nemotron3Diarizer(config: Self.config, models: try await loadedModels())
        var probabilities: [Float] = []
        var frames = 0
        let collect = { (results: [Nemotron3ChunkResult]) in
            for result in results {
                probabilities += result.probabilities
                frames += result.frameCount
            }
        }
        for start in stride(from: 0, to: samples.count, by: Self.blockSamples) {
            try Task.checkCancellation()
            let end = min(start + Self.blockSamples, samples.count)
            diarizer.appendAudio(Array(samples[start..<end]))
            collect(try diarizer.processBufferedAudio())
            progress(Double(end) / Double(samples.count))
        }
        collect(try diarizer.finishStream())
        return Nemotron3Diarizer.segments(probabilities: probabilities, frameCount: frames).map {
            SpeakerSpan(speaker: String($0.speakerIndex), start: Double($0.startSeconds), end: Double($0.endSeconds))
        }
    }
}
