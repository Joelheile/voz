import CoreML
import FluidAudio
import Foundation
import Synchronization

/// Loads a FluidAudio model cache so a broken cache can't crash Voz at every launch.
///
/// FluidAudio counts a bundle as complete once `coremldata.bin` exists, so an interrupted download can leave one without
/// `model.mil`, and CoreML segfaults on it instead of throwing (FluidAudio #1147). Two processes downloading the same
/// model, such as Voz and its test build, also write into one file and break it. The guard:
/// - holds a file lock next to the cache for the whole load, so only one process downloads or loads it at a time,
/// - deletes a bundle that lacks its program or weights, so FluidAudio downloads it again,
/// - marks the load as running once CoreML starts, the only step that can crash. A load still marked at the next start
///   either crashed or Voz quit while CoreML compiled, so the guard loads the cache in a child process first and deletes
///   it only when that child fails. After three unfinished loads in one build it stops loading the model.
///   Quitting during a download leaves no mark, so the download resumes.
struct ModelLoadGuard {
    static let unfinishedLoadsBeforeSkip = 3

    let cache: URL
    /// Files outside the bundles that the load needs but FluidAudio doesn't fetch again when they go missing
    var files: Set<String> = []
    let build: String
    /// Whether CoreML loads the cache, checked in a child process so a segfault can't end Voz
    var loadsInChild: @Sendable (URL) async -> Bool = ModelProbe.loads

    private var marker: URL { cache.deletingLastPathComponent().appendingPathComponent("\(cache.lastPathComponent).voz-load.json") }
    private var lockFile: URL { cache.deletingLastPathComponent().appendingPathComponent("\(cache.lastPathComponent).voz-load.lock") }

    /// Returns nil without loading when three loads in this build never finished.
    /// `load` calls `start.coreML()` when CoreML starts compiling or loading the models.
    func run<T>(_ load: (_ start: LoadStart) async throws -> T) async throws -> T? {
        let lock = try await acquireLock()
        defer { lock.release() }
        guard try await begin() else { return nil }
        do {
            let value = try await load(LoadStart { [self] in try markCoreML() })
            try finish()
            return value
        } catch {
            try finish()
            throw error
        }
    }

    /// Deletes the cache once no process is loading it
    func remove() async throws {
        let lock = try await acquireLock()
        defer { lock.release() }
        try delete(cache)
    }

    /// Call with the lock held. Every load that ends clears the mark, so a load still marked crashed or was quit in CoreML.
    func begin() async throws -> Bool {
        let state = savedState()
        let unfinished = state.unfinished + (state.inCoreML ? 1 : 0)
        try save(LoadState(build: build, unfinished: unfinished, inCoreML: false))
        guard unfinished < Self.unfinishedLoadsBeforeSkip else { return false }
        if missesFiles() {
            try delete(cache)
            return true
        }
        try brokenBundles().forEach(delete)
        if state.inCoreML, FileManager.default.fileExists(atPath: cache.path), await !loadsInChild(cache) {
            Log.app.error("\(cache.lastPathComponent, privacy: .public) crashed CoreML, so Voz downloads it again")
            try delete(cache)
        }
        return true
    }

    func markCoreML() throws {
        let state = savedState()
        try save(LoadState(build: build, unfinished: state.unfinished, inCoreML: true))
    }

    private func finish() throws {
        try save(LoadState(build: build, unfinished: 0, inCoreML: false))
    }

    private func missesFiles() -> Bool {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: cache.path) else { return false }
        return files.contains { !fileManager.fileExists(atPath: cache.appendingPathComponent($0).path) }
    }

    private func brokenBundles() -> [URL] {
        Self.contents(of: cache).filter { $0.pathExtension == "mlmodelc" && Self.isBroken(bundle: $0) }
    }

    /// A bundle FluidAudio would load, with `coremldata.bin` and no `.partial` file still downloading, that lacks its program or weights
    private static func isBroken(bundle: URL) -> Bool {
        func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: bundle.appendingPathComponent(path).path) }
        let downloading = contents(of: bundle).contains { $0.pathExtension == "partial" }
        guard exists("coremldata.bin"), !downloading else { return false }
        guard let program = try? String(contentsOf: bundle.appendingPathComponent("model.mil"), encoding: .utf8) else { return true }
        return program.contains("weights/weight.bin") && !exists("weights/weight.bin")
    }

    private static func contents(of directory: URL) -> [URL] {
        FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? []
    }

    private func delete(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func acquireLock() async throws -> FileLock {
        try FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        return try await FileLock.acquire(lockFile)
    }

    private func savedState() -> LoadState {
        guard let data = try? Data(contentsOf: marker), let state = try? JSONDecoder().decode(LoadState.self, from: data), state.build == build else {
            return LoadState(build: build, unfinished: 0, inCoreML: false)
        }
        return state
    }

    private func save(_ state: LoadState) throws {
        try JSONEncoder().encode(state).write(to: marker, options: .atomic)
    }
}

/// Marks the load once, from whichever thread reports that CoreML started
final class LoadStart: Sendable {
    private let marked = Mutex(false)
    private let mark: @Sendable () throws -> Void

    init(_ mark: @escaping @Sendable () throws -> Void) {
        self.mark = mark
    }

    func coreML() {
        let first = marked.withLock { marked in
            defer { marked = true }
            return !marked
        }
        guard first else { return }
        do {
            try mark()
        } catch {
            Log.app.error("Could not mark the model load: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// For FluidAudio progress handlers
    func coreML(on progress: DownloadProgress) {
        if case .compiling = progress.phase { coreML() }
    }
}

private struct LoadState: Codable {
    let build: String
    /// Loads in a row that reached CoreML and never finished
    let unfinished: Int
    let inCoreML: Bool
}

enum ModelProbe {
    /// Runs `voz --check-models` on the cache. A crash or error there means CoreML can't load it.
    static func loads(_ cache: URL) async -> Bool {
        guard let executable = Bundle.main.executableURL else { return false }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["--check-models", cache.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return await withCheckedContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationReason == .exit && $0.terminationStatus == 0) }
            do {
                try process.run()
            } catch {
                Log.app.error("Could not check \(cache.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                continuation.resume(returning: false)
            }
        }
    }

    /// Loads every bundle in the folder with CoreML. Exit code 0 when all load.
    @MainActor static func check(_ cache: URL) -> Int32 {
        let items = FileManager.default.enumerator(at: cache, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? []
        for bundle in items where bundle.pathExtension == "mlmodelc" {
            do {
                _ = try MLModel(contentsOf: bundle)
            } catch {
                Headless.printError("\(bundle.lastPathComponent) does not load: \(error.localizedDescription)")
                return 1
            }
        }
        return 0
    }
}

/// An exclusive `flock`. The kernel drops it when the process exits or crashes, so it never goes stale.
private struct FileLock {
    static let retryDelay = Duration.milliseconds(200)

    let descriptor: Int32

    static func acquire(_ url: URL) async throws -> FileLock {
        let descriptor = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            let code = errno
            do {
                guard code == EWOULDBLOCK else { throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO) }
                try await Task.sleep(for: retryDelay)
            } catch {
                close(descriptor)
                throw error
            }
        }
        return FileLock(descriptor: descriptor)
    }

    func release() {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}

extension ModelLoadGuard {
    static let vocabularyModel = ModelLoadGuard(
        cache: CtcModels.defaultCacheDirectory(),
        files: [ModelNames.CTC.vocabularyPath, "tokenizer.json"],
        build: SystemContext.appVersion
    )

    static let speakerModel = ModelLoadGuard(
        cache: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FluidAudio/Models/\(Repo.nemotron3Diarization.folderName)"),
        build: SystemContext.appVersion
    )

    static func speechModel(_ version: AsrModelVersion) -> ModelLoadGuard {
        ModelLoadGuard(cache: AsrModels.defaultCacheDirectory(for: version), build: SystemContext.appVersion)
    }
}

extension Nemotron3Models {
    /// Runs on the GPU so it doesn't wait for the Neural Engine, which Parakeet uses at the same time.
    /// FluidAudio reports no compiling step here, so the load counts as in CoreML once the bundle is on disk.
    static func loadGuarded(config: Nemotron3Config) async throws -> Nemotron3Models {
        let speakers = ModelLoadGuard.speakerModel
        let manifest = speakers.cache.appendingPathComponent("\(config.hubSubdirectory)/\(config.modelFileName)/coremldata.bin")
        let models = try await speakers.run { start in
            if FileManager.default.fileExists(atPath: manifest.path) { start.coreML() }
            return try await loadFromHuggingFace(config: config, computeUnits: .cpuAndGPU)
        }
        guard let models else { throw TranscriberError.modelKeepsFailing }
        return models
    }
}
