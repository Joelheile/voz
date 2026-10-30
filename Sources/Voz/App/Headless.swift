import FluidAudio
import Foundation
import Synchronization

@MainActor
enum Headless {
    private nonisolated static let flags = ["--transcribe", "--benchmark-speech", "--clean", "--eval", "--simulate-dictation", "--render-design", "--measure-recorder"]

    nonisolated static func handles(_ arguments: [String]) -> Bool {
        flags.contains(where: arguments.contains)
    }

    static func run(_ arguments: [String]) async -> Int32 {
        if let path = value(of: "--benchmark-speech", in: arguments) {
            guard let repeats = Int(value(of: "--repeat", in: arguments) ?? "10"),
                  (2...1000).contains(repeats),
                  let model = SpeechModel(rawValue: value(of: "--model", in: arguments) ?? SpeechModel.parakeetUltra.rawValue) else {
                printError("Speech benchmark requires a known model and 2...1000 repeats")
                return 64
            }
            return await SpeechBenchmark.run(path: path, model: model, repeats: repeats, vocabulary: vocabulary(in: arguments))
        }
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
            guard let repeats = Int(value(of: "--repeat", in: arguments) ?? "1"),
                  (1...1000).contains(repeats),
                  let budget = Int(value(of: "--budget-ms", in: arguments) ?? String(CleanupBudget.total.wholeMilliseconds)),
                  (1...60_000).contains(budget) else {
                printError("Evaluation requires 1...1000 repeats and a 1...60000 ms budget")
                return 64
            }
            return await CleanupEval.run(path: path, repeats: repeats, budget: .milliseconds(budget))
        }
        if let path = value(of: "--transcribe", in: arguments) {
            let url = URL(fileURLWithPath: path)
            guard arguments.contains("--speakers") else { return await transcribe(url, arguments: arguments) }
            return await transcribeSpeakers(url, model: speechModel(in: arguments))
        }
        if let seconds = value(of: "--measure-recorder", in: arguments).flatMap(Double.init) {
            return await measureRecorder(seconds: seconds)
        }
        if let path = value(of: "--simulate-dictation", in: arguments) {
            return await simulateDictation(URL(fileURLWithPath: path), arguments: arguments)
        }
        let models = SpeechModel.allCases.map(\.rawValue).joined(separator: "|")
        printError("usage: voz --transcribe <audio file> [--model \(models)] [--vocab a,b] [--speakers]\n       voz --benchmark-speech <audio file> [--model \(models)] [--repeat 2...1000] [--vocab a,b]\n       voz --clean <text> [--vocab a,b]\n       voz --eval <cases.json> [--repeat n] [--budget-ms n]\n       voz --simulate-dictation <audio file> [--model \(models)] [--speed n] [--no-cleanup]\n       voz --measure-recorder <seconds>\n       voz --render-design <directory>")
        return 64
    }

    private static func transcribe(_ url: URL, arguments: [String]) async -> Int32 {
        let model = speechModel(in: arguments)
        let words = vocabulary(in: arguments)
        let transcriber = Transcriber()
        let engine = SpeechEngine(parakeet: transcriber)
        let loadStart = Date()
        do {
            try await engine.prepare(model)
            if model != .appleSpeech {
                try await transcriber.prepareVocabulary(words.map { VocabularyTerm(word: $0, aliases: []) })
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

    private static func transcribeSpeakers(_ url: URL, model: SpeechModel) async -> Int32 {
        let start = Date()
        do {
            let transcript = try await FileTranscriber(transcriber: Transcriber(), vocabulary: nil).transcribe(url, model: model, speakers: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
            print(String(decoding: try encoder.encode(transcript), as: UTF8.self))
            print(String(format: "audio %.1fs, total %.1fs", transcript.seconds, Date().timeIntervalSince(start)))
            return 0
        } catch {
            printError("transcription failed: \(error)")
            return 1
        }
    }

    private static func simulateDictation(_ url: URL, arguments: [String]) async -> Int32 {
        let model = speechModel(in: arguments)
        guard let speed = Double(value(of: "--speed", in: arguments) ?? "1"), (0.01...100).contains(speed) else {
            printError("Simulation speed must be between 0.01 and 100")
            return 64
        }
        let cleanupEnabled = !arguments.contains("--no-cleanup")
        let transcriber = Transcriber()
        let engine = SpeechEngine(parakeet: transcriber)
        let cleaner = TextCleaner()
        do {
            try await engine.prepare(model)
            try await transcriber.prepareVocabulary([])
            let samples = try AudioConverter().resampleAudioFile(url)
            cleaner.prewarm(prompt: CleanupPrompt.standard, vocabulary: [])
            try? await Task.sleep(for: .seconds(1))
            _ = await cleaner.clean("Warm up the cleanup model before we start timing anything.", prompt: CleanupPrompt.standard, vocabulary: [])
            let session = StreamingDictation(
                transcribe: { try await engine.transcribe($0, model: model, vocabulary: []) },
                cleaner: cleaner,
                vocabulary: [],
                plan: Task { CleanupPlan(prompt: CleanupPrompt.standard, mode: .heavy) },
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
            print("audio_s=\(Int(transcript.audioSeconds)) release_to_text_ms=\(latency) segments=\(transcript.segmentCount) units=\(transcript.unitCount) cleaned_in_time=\(transcript.cleanedInTime) tail_stt_ms=\(transcript.sttMs) cleanup_wait_ms=\(transcript.cleaned.milliseconds) timed_out=\(transcript.cleaned.timedOut)")
            return 0
        } catch {
            printError("simulation failed: \(error)")
            return 1
        }
    }

    private static func measureRecorder(seconds: Double) async -> Int32 {
        guard seconds > 0, seconds <= 60 else {
            printError("Recorder measurement must be greater than zero and at most 60 seconds")
            return 64
        }
        await Permissions.requestMicrophone()
        guard Permissions.microphoneGranted else {
            printError("Microphone permission is required. Grant access in System Settings, then retry.")
            return 77
        }
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
            print("prepared=\(prepared) start_call_ms=\((started - begin).wholeMilliseconds) first_sample_ms=\(first.map { String($0.wholeMilliseconds) } ?? "none") samples=\(samples.count) rms=\(AudioLevel.rms(of: samples))")
            try? await Task.sleep(for: .milliseconds(500))
            print("mic_running_after_stop=\(InputDevice.isRunningSomewhere())")
        }
        return 0
    }

    private static func clean(_ text: String, vocabulary: [String]) async -> Int32 {
        let cleaner = TextCleaner()
        cleaner.prewarm(prompt: CleanupPrompt.standard, vocabulary: vocabulary)
        try? await Task.sleep(for: .seconds(1))
        let result = await cleaner.clean(text, prompt: CleanupPrompt.standard, vocabulary: vocabulary)
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

    static func printError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}

final class FirstSample: Sendable {
    private let instant = Mutex<ContinuousClock.Instant?>(nil)

    func mark() {
        instant.withLock { if $0 == nil { $0 = .now } }
    }

    func elapsed(since begin: ContinuousClock.Instant, clock: ContinuousClock) -> Duration? {
        instant.withLock { $0.map { $0 - begin } }
    }
}
