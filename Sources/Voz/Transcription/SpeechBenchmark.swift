import FluidAudio
import Foundation

enum SpeechBenchmarkError: Error {
    case emptyAudio
    case emptyTranscript(run: Int)
    case wrongModel(expected: String, actual: String)
    case timedOut
}

@MainActor
enum SpeechBenchmark {
    private struct Run: Encodable {
        let milliseconds: Int
        let engineMilliseconds: Int
        let text: String
    }

    private struct Report: Encodable {
        let model: String
        let operatingSystem: String
        let audioSeconds: Double
        let resampleMilliseconds: Int
        let preparationMilliseconds: Int
        let firstMilliseconds: Int
        let warmP50Milliseconds: Int
        let warmP95Milliseconds: Int
        let runs: [Run]
    }

    static func run(path: String, model: SpeechModel, repeats: Int, vocabulary: [String]) async -> Int32 {
        do {
            let resampleStart = ContinuousClock.now
            let samples = try AudioConverter().resampleAudioFile(URL(fileURLWithPath: path))
            guard !samples.isEmpty else { throw SpeechBenchmarkError.emptyAudio }
            let resampleMs = (ContinuousClock.now - resampleStart).wholeMilliseconds
            let parakeet = Transcriber()
            let engine = SpeechEngine(parakeet: parakeet)
            let preparationStart = ContinuousClock.now
            try await engine.prepare(model)
            if model != .appleSpeech {
                try await parakeet.prepareVocabulary(vocabulary.map { VocabularyTerm(word: $0, aliases: []) })
            }
            let preparationMs = (ContinuousClock.now - preparationStart).wholeMilliseconds
            var runs: [Run] = []
            for index in 0..<repeats {
                let started = ContinuousClock.now
                let result = try await withTimeout(.seconds(60), onTimeout: SpeechBenchmarkError.timedOut) {
                    try await engine.transcribe(samples, model: model, vocabulary: vocabulary)
                }
                let milliseconds = (ContinuousClock.now - started).wholeMilliseconds
                guard result.model == model.rawValue else {
                    throw SpeechBenchmarkError.wrongModel(expected: model.rawValue, actual: result.model)
                }
                guard !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw SpeechBenchmarkError.emptyTranscript(run: index + 1)
                }
                runs.append(Run(milliseconds: milliseconds, engineMilliseconds: Int(result.processingSeconds * 1000), text: result.text))
            }
            let warm = runs.dropFirst().map(\.milliseconds).sorted()
            let report = Report(
                model: model.rawValue,
                operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
                audioSeconds: Double(samples.count) / RecordingFilter.sampleRate,
                resampleMilliseconds: resampleMs,
                preparationMilliseconds: preparationMs,
                firstMilliseconds: runs[0].milliseconds,
                warmP50Milliseconds: warm[Int(ceil(Double(warm.count) * 0.5)) - 1],
                warmP95Milliseconds: warm[Int(ceil(Double(warm.count) * 0.95)) - 1],
                runs: runs
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            FileHandle.standardOutput.write(try encoder.encode(report))
            print()
            return 0
        } catch {
            Headless.printError("speech benchmark failed for \(model.rawValue): \(error)")
            return 1
        }
    }
}
