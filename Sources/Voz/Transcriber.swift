import FluidAudio
import Foundation
import VozCore

struct TranscriptionResult: Sendable {
    let text: String
    let audioSeconds: Double
    let processingSeconds: Double
    let model: String
}

actor Transcriber {
    typealias StatusReport = @Sendable (LanguageMode, ModelState) -> Void

    private var loaded: (mode: LanguageMode, manager: AsrManager)?
    private var loading: (mode: LanguageMode, task: Task<AsrManager, Error>)?
    private let report: StatusReport
    private let booster = VocabularyBooster()

    init(report: @escaping StatusReport = { _, _ in }) {
        self.report = report
    }

    func isReady(_ mode: LanguageMode) -> Bool {
        loaded?.mode == mode
    }

    func prepareVocabulary(_ words: [String]) async throws {
        try await booster.prepare(words: words)
    }

    func prepare(_ mode: LanguageMode) async throws {
        _ = try await manager(for: mode)
    }

    func removeUnusedModels(keeping mode: LanguageMode) {
        for other in LanguageMode.allCases where other != mode && loading?.mode != other {
            let directory = AsrModels.defaultCacheDirectory(for: other.modelVersion)
            guard FileManager.default.fileExists(atPath: directory.path) else { continue }
            do {
                try FileManager.default.removeItem(at: directory)
                report(other, .notLoaded)
                Log.app.notice("Removed unused model \(other.modelName)")
            } catch {
                Log.app.error("Removing unused model \(other.modelName) failed: \(error.localizedDescription, privacy: .private)")
            }
        }
    }

    func transcribe(_ samples: [Float], mode: LanguageMode, vocabulary: [String]) async throws -> TranscriptionResult {
        let manager = try await manager(for: mode)
        var decoderState = TdtDecoderState.make()
        let result = try await manager.transcribe(samples, decoderState: &decoderState)
        let text = await booster.rescore(result, samples: samples, words: vocabulary)
        return TranscriptionResult(text: text, audioSeconds: result.duration, processingSeconds: result.processingTime, model: mode.modelName)
    }

    func transcribeFile(_ url: URL, mode: LanguageMode, vocabulary: [String]) async throws -> TranscriptionResult {
        let samples = try AudioConverter().resampleAudioFile(url)
        return try await transcribe(samples, mode: mode, vocabulary: vocabulary)
    }

    private func manager(for mode: LanguageMode) async throws -> AsrManager {
        if let loaded, loaded.mode == mode { return loaded.manager }
        let task: Task<AsrManager, Error>
        if let loading, loading.mode == mode {
            task = loading.task
        } else {
            task = makeLoadTask(for: mode)
            loading = (mode, task)
        }
        do {
            let manager = try await task.value
            loaded = (mode, manager)
            if loading?.mode == mode { loading = nil }
            return manager
        } catch {
            if loading?.mode == mode { loading = nil }
            report(mode, .failed(error.localizedDescription))
            throw error
        }
    }

    private func makeLoadTask(for mode: LanguageMode) -> Task<AsrManager, Error> {
        let report = report
        let version = mode.modelVersion
        return Task {
            let loadStart = ContinuousClock.now
            report(mode, .downloading(fraction: 0))
            let models = try await AsrModels.downloadAndLoad(version: version) { progress in
                switch progress.phase {
                case .listing, .downloading:
                    report(mode, .downloading(fraction: progress.fractionCompleted))
                case .compiling:
                    report(mode, .compiling)
                }
            }
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)
            let loadMs = (ContinuousClock.now - loadStart).wholeMilliseconds
            let warmStart = ContinuousClock.now
            await Self.warmUp(manager)
            let warmMs = (ContinuousClock.now - warmStart).wholeMilliseconds
            Log.app.notice("Parakeet \(mode.modelName) cold load \(loadMs) ms, warm-up \(warmMs) ms")
            report(mode, .ready(bytes: Self.directorySize(AsrModels.defaultCacheDirectory(for: version))))
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

extension LanguageMode {
    var isDownloaded: Bool {
        AsrModels.modelsExist(at: AsrModels.defaultCacheDirectory(for: modelVersion), version: modelVersion)
    }

    var modelVersion: AsrModelVersion {
        switch self {
        case .automatic: .v3
        case .english: .v2
        }
    }
}
