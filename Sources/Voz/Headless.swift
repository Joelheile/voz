import FluidAudio
import Foundation
import VozCore

@MainActor
enum Headless {
    static func run(_ arguments: [String]) async -> Int32? {
        if let text = value(of: "--clean", in: arguments) {
            return await clean(text, vocabulary: vocabulary(in: arguments))
        }
        if let directory = value(of: "--render-design", in: arguments) {
            do {
                try await DesignRender.run(outputDirectory: URL(fileURLWithPath: directory))
                return 0
            } catch {
                printError("render failed: \(error)")
                return 1
            }
        }
        if let path = value(of: "--eval", in: arguments) {
            return await CleanupEval.run(
                path: path,
                repeats: value(of: "--repeat", in: arguments).flatMap(Int.init) ?? 1,
                budget: value(of: "--budget-ms", in: arguments).flatMap(Int.init).map { Duration.milliseconds($0) } ?? CleanupBudget.total
            )
        }
        if let path = value(of: "--transcribe", in: arguments) {
            return await transcribe(URL(fileURLWithPath: path), arguments: arguments)
        }
        if let seconds = value(of: "--measure-recorder", in: arguments).flatMap(Double.init) {
            return await measureRecorder(seconds: seconds)
        }
        if let path = value(of: "--simulate-dictation", in: arguments) {
            return await simulateDictation(URL(fileURLWithPath: path), arguments: arguments)
        }
        if ["--transcribe", "--clean", "--eval", "--simulate-dictation", "--render-design", "--measure-recorder"].contains(where: arguments.contains) {
            printError("usage: voz --transcribe <audio file> [--model parakeet-ultra|parakeet-tdt-v2|apple-speech] [--vocab a,b]\n       voz --clean <text> [--vocab a,b]\n       voz --eval <cases.json> [--repeat n] [--budget-ms n]\n       voz --simulate-dictation <audio file> [--model parakeet-ultra|parakeet-tdt-v2|apple-speech] [--speed n] [--no-cleanup]")
            return 64
        }
        return nil
    }

    private static func transcribe(_ url: URL, arguments: [String]) async -> Int32 {
        let model = speechModel(in: arguments)
        let words = vocabulary(in: arguments)
        let transcriber = Transcriber()
        let engine = SpeechEngine(parakeet: transcriber)
        let loadStart = Date()
        do {
            if model != .appleSpeech {
                try await transcriber.prepare(model)
                try await transcriber.prepareVocabulary(words)
            }
            let loadSeconds = Date().timeIntervalSince(loadStart)
            let result = try await engine.transcribeFile(url, model: model, vocabulary: words)
            print(result.text)
            print(String(
                format: "engine %@, load %.2fs, audio %.2fs, transcription %.3fs",
                result.model, loadSeconds, result.audioSeconds, result.processingSeconds
            ))
            return 0
        } catch {
            printError("transcription failed: \(error)")
            return 1
        }
    }

    private static func simulateDictation(_ url: URL, arguments: [String]) async -> Int32 {
        let model = speechModel(in: arguments)
        let speed = value(of: "--speed", in: arguments).flatMap(Double.init) ?? 1
        let cleanupEnabled = !arguments.contains("--no-cleanup")
        let transcriber = Transcriber()
        let cleaner = TextCleaner()
        do {
            try await transcriber.prepare(model)
            try await transcriber.prepareVocabulary([])
            let samples = try AudioConverter().resampleAudioFile(url)
            cleaner.prewarm(vocabulary: [])
            try? await Task.sleep(for: .seconds(1))
            _ = await cleaner.clean("Warm up the cleanup model before we start timing anything.", vocabulary: [])
            let session = StreamingDictation(
                engine: SpeechEngine(parakeet: transcriber),
                cleaner: cleaner,
                model: model,
                vocabulary: [],
                cleanupEnabled: cleanupEnabled
            )
            let clock = ContinuousClock()
            let chunkSamples = 512
            let chunkDuration = Duration.seconds(Double(chunkSamples) / RecordingFilter.sampleRate / speed)
            let start = clock.now
            for (index, offset) in stride(from: 0, to: samples.count, by: chunkSamples).enumerated() {
                try await Task.sleep(until: start + chunkDuration * (index + 1), clock: clock)
                session.feed(Array(samples[offset..<min(offset + chunkSamples, samples.count)]))
            }
            let released = clock.now
            guard let transcript = try await session.finish(samples: samples, released: released) else {
                printError("empty transcript")
                return 1
            }
            let latency = (clock.now - released).wholeMilliseconds
            print("raw: \(transcript.raw)")
            print("final: \(transcript.cleaned.text)")
            print("audio_s=\(Int(transcript.audioSeconds)) release_to_text_ms=\(latency) segments=\(transcript.segmentCount) cleaned_in_time=\(transcript.cleanedInTime) tail_stt_ms=\(transcript.sttMs) cleanup_wait_ms=\(transcript.cleaned.milliseconds) timed_out=\(transcript.cleaned.timedOut)")
            return 0
        } catch {
            printError("simulation failed: \(error)")
            return 1
        }
    }

    private static func measureRecorder(seconds: Double) async -> Int32 {
        setvbuf(stdout, nil, _IONBF, 0)
        let recorder = Recorder()
        for prepared in [false, true, true] {
            if prepared {
                recorder.prepare()
                try? await Task.sleep(for: .seconds(1))
                print("mic_running_while_prepared=\(InputDevice.isRunningSomewhere())")
            }
            let clock = ContinuousClock()
            let firstSample = FirstSample()
            recorder.onSamples = { _ in firstSample.mark() }
            let begin = clock.now
            do {
                try recorder.start()
            } catch {
                printError("recorder failed: \(error)")
                return 1
            }
            let started = clock.now
            try? await Task.sleep(for: .seconds(seconds))
            let samples = recorder.stop()
            let first = firstSample.elapsed(since: begin, clock: clock)
            print("prepared=\(prepared) start_call_ms=\((started - begin).wholeMilliseconds) first_sample_ms=\(first.map { String($0.wholeMilliseconds) } ?? "none") samples=\(samples.count)")
            try? await Task.sleep(for: .milliseconds(500))
            print("mic_running_after_stop=\(InputDevice.isRunningSomewhere())")
        }
        return 0
    }

    private static func clean(_ text: String, vocabulary: [String]) async -> Int32 {
        let cleaner = TextCleaner()
        cleaner.prewarm(vocabulary: vocabulary)
        try? await Task.sleep(for: .seconds(1))
        let result = await cleaner.clean(text, vocabulary: vocabulary)
        print(result.text)
        print("cleanup \(result.milliseconds) ms, fillers removed \(result.fillerWordsRemoved), timed out \(result.timedOut)")
        return 0
    }

    private static func value(of flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    private static func speechModel(in arguments: [String]) -> SpeechModel {
        value(of: "--model", in: arguments).flatMap(SpeechModel.init) ?? .parakeetUltra
    }

    private static func vocabulary(in arguments: [String]) -> [String] {
        value(of: "--vocab", in: arguments)?.split(separator: ",").map(String.init) ?? []
    }

    private static func printError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}

final class FirstSample: @unchecked Sendable {
    private let lock = NSLock()
    private var instant: ContinuousClock.Instant?

    func mark() {
        lock.withLock { if instant == nil { instant = .now } }
    }

    func elapsed(since begin: ContinuousClock.Instant, clock: ContinuousClock) -> Duration? {
        lock.withLock { instant.map { $0 - begin } }
    }
}
