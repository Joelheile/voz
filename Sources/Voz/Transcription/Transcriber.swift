import FluidAudio
import Foundation

struct TranscriptionResult: Sendable {
    let text: String
    let audioSeconds: Double
    let processingSeconds: Double
    let model: String
}

enum TranscriberError: Error {
    case notParakeet(String)
    case superseded
}

actor Transcriber {
    typealias StatusReport = @Sendable (SpeechModel, ModelState) -> Void

    private var loaded: (model: SpeechModel, manager: AsrManager)?
    private var loading: (model: SpeechModel, task: Task<AsrManager, Error>)?
    private let report: StatusReport
    private let booster = VocabularyBooster()
    private static let downloadableVersions: [AsrModelVersion] = [.ultra, .redux, .v2, .v3]

    init(report: @escaping StatusReport = { _, _ in }) {
        self.report = report
    }

    func isReady(_ model: SpeechModel) -> Bool {
        loaded?.model == model
    }

    func prepareVocabulary(_ words: [String]) async throws {
        try await booster.prepare(words: words)
    }

    func prepare(_ model: SpeechModel) async throws {
        guard model.modelVersion != nil else {
            loading?.task.cancel()
            loading = nil
            return
        }
        _ = try await manager(for: model)
    }

    func removeUnusedModels(keeping model: SpeechModel) {
        let inUse = [model.modelVersion, loading?.model.modelVersion].compactMap { $0 }
        for version in Self.downloadableVersions where !inUse.contains(version) {
            let directory = AsrModels.defaultCacheDirectory(for: version)
            guard FileManager.default.fileExists(atPath: directory.path) else { continue }
            do {
                try FileManager.default.removeItem(at: directory)
                if let removed = SpeechModel.allCases.first(where: { $0.modelVersion == version }) {
                    report(removed, .notLoaded)
                }
                Log.app.notice("Removed unused model \(directory.lastPathComponent)")
            } catch {
                Log.app.error("Removing unused model \(directory.lastPathComponent) failed: \(error.localizedDescription, privacy: .private)")
            }
        }
    }

    func transcribe(_ samples: [Float], model: SpeechModel, vocabulary: [String]) async throws -> TranscriptionResult {
        let manager = try await manager(for: model)
        var decoderState = TdtDecoderState.make()
        let result = try await manager.transcribe(samples, decoderState: &decoderState)
        let text = await booster.rescore(result, samples: samples, words: vocabulary)
        return TranscriptionResult(text: text, audioSeconds: result.duration, processingSeconds: result.processingTime, model: model.rawValue)
    }

    private func manager(for model: SpeechModel) async throws -> AsrManager {
        if let loaded, loaded.model == model { return loaded.manager }
        let task: Task<AsrManager, Error>
        if let loading, loading.model == model {
            task = loading.task
        } else {
            loading?.task.cancel()
            task = makeLoadTask(for: model)
            loading = (model, task)
        }
        defer { if loading?.task == task { loading = nil } }
        do {
            let manager = try await task.value
            guard !task.isCancelled else { throw CancellationError() }
            loaded = (model, manager)
            return manager
        } catch where task.isCancelled {
            report(model, .notLoaded)
            throw TranscriberError.superseded
        } catch {
            Log.app.error("Model \(model.rawValue) failed: \(error.localizedDescription, privacy: .public)")
            report(model, .failed(model.isDownloaded ? "Could not load the model" : "Download failed. Check your connection"))
            throw error
        }
    }

    private func makeLoadTask(for model: SpeechModel) -> Task<AsrManager, Error> {
        let report = report
        return Task {
            guard let version = model.modelVersion else { throw TranscriberError.notParakeet(model.rawValue) }
            let loadStart = ContinuousClock.now
            report(model, .downloading(fraction: 0))
            let models = try await AsrModels.downloadAndLoad(version: version) { progress in
                switch progress.phase {
                case .listing, .downloading:
                    report(model, .downloading(fraction: progress.fractionCompleted))
                case .compiling:
                    report(model, .compiling)
                }
            }
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)
            let loadMs = (ContinuousClock.now - loadStart).wholeMilliseconds
            let warmStart = ContinuousClock.now
            await Self.warmUp(manager)
            let warmMs = (ContinuousClock.now - warmStart).wholeMilliseconds
            Log.app.notice("Parakeet \(model.rawValue) cold load \(loadMs) ms, warm-up \(warmMs) ms")
            report(model, .ready(bytes: Self.directorySize(AsrModels.defaultCacheDirectory(for: version))))
            return manager
        }
    }

    private static func warmUp(_ manager: AsrManager) async {
        var decoderState = TdtDecoderState.make()
        do {
            _ = try await manager.transcribe([Float](repeating: 0, count: Int(RecordingFilter.sampleRate)), decoderState: &decoderState)
        } catch {
            Log.app.error("Parakeet warm-up failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    private static func directorySize(_ directory: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey]
        let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: keys)
        return (files?.allObjects as? [URL] ?? []).reduce(0) { total, url in
            let size = (try? url.resourceValues(forKeys: Set(keys)).totalFileAllocatedSize) ?? 0
            return total + Int64(size)
        }
    }
}

extension SpeechModel {
    var isDownloaded: Bool {
        guard let modelVersion else { return true }
        return AsrModels.modelsExist(at: AsrModels.defaultCacheDirectory(for: modelVersion), version: modelVersion)
    }

    var modelVersion: AsrModelVersion? {
        switch self {
        case .parakeetUltra: .ultra
        case .parakeetEnglish: .v2
        case .appleSpeech: nil
        }
    }
}

final class SpeechEngine: Sendable {
    private let parakeet: Transcriber
    private let apple = AppleSpeechTranscriber()

    init(parakeet: Transcriber) {
        self.parakeet = parakeet
    }

    func prepare(_ model: SpeechModel) async throws {
        try await parakeet.prepare(model)
        if model == .appleSpeech {
            try await apple.prepare(locale: Self.locale)
        }
    }

    func transcribe(_ samples: [Float], model: SpeechModel, vocabulary: [String]) async throws -> TranscriptionResult {
        if await parakeet.isReady(model) {
            return try await parakeet.transcribe(samples, model: model, vocabulary: vocabulary)
        }
        if model != .appleSpeech { Log.app.notice("Parakeet not ready, using Apple speech") }
        return try await apple.transcribe(samples, locale: Self.locale, vocabulary: vocabulary)
    }

    func transcribeFile(_ url: URL, model: SpeechModel, vocabulary: [String]) async throws -> TranscriptionResult {
        let samples = try AudioConverter().resampleAudioFile(url)
        return try await transcribe(samples, model: model, vocabulary: vocabulary)
    }

    static var locale: Locale {
        Locale.current.language.languageCode == "de" ? Locale(identifier: "de_DE") : Locale(identifier: "en_US")
    }
}
