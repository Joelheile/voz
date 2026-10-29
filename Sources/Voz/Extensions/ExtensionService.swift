import CoreServices
import Foundation

struct ExtensionDelivery {
    let text: String
    let command: VoiceCommandMatch?
}

@MainActor
final class ExtensionCatalog: ObservableObject {
    @Published fileprivate(set) var loaded: [String] = []
    @Published fileprivate(set) var errors: [String: String] = [:]
    @Published fileprivate(set) var commands: [ExtensionCommand] = []
    @Published fileprivate(set) var speechModels: [HostComponent] = []
    @Published fileprivate(set) var cleanupModels: [HostComponent] = []
    @Published fileprivate(set) var cleanupSteps: [HostComponent] = []
    @Published fileprivate(set) var actions: [ExtensionAction] = []
    @Published fileprivate(set) var settings: [ExtensionSettings] = []
    @Published fileprivate(set) var hostError: String?
    fileprivate var perform: (ExtensionAction) -> Void = { _ in }

    func run(_ action: ExtensionAction) {
        perform(action)
    }

    func settings(for name: String) -> [ExtensionSettings] {
        settings.filter { Self.belongs($0.extension, to: name) }
    }

    func commands(for name: String) -> [ExtensionCommand] {
        commands.filter { Self.belongs($0.extension, to: name) }
    }

    func cleanupSteps(for name: String) -> [HostComponent] {
        cleanupSteps.filter { Self.belongs($0.id, to: name) }
    }

    func actions(for name: String) -> [ExtensionAction] {
        actions.filter { Self.belongs($0.extension, to: name) }
    }

    func error(for name: String) -> String? {
        errors.first { Self.belongs($0.key, to: name) }?.value ?? hostError
    }

    func isLoaded(_ name: String) -> Bool {
        loaded.contains { Self.belongs($0, to: name) } || error(for: name) != nil
    }

    private static func belongs(_ extension: String, to name: String) -> Bool {
        `extension` == name || `extension`.hasPrefix("\(name)/")
    }

    fileprivate func show(_ manifest: HostManifest?) {
        loaded = manifest?.extensions ?? []
        commands = manifest?.commands ?? []
        errors = Dictionary(manifest?.errors.map { ($0.extension, $0.message) } ?? [], uniquingKeysWith: { first, _ in first })
        speechModels = manifest?.speechModels ?? []
        cleanupModels = manifest?.cleanupModels ?? []
        cleanupSteps = manifest?.cleanupSteps ?? []
        actions = manifest?.actions ?? []
        settings = manifest?.settings ?? []
        hostError = nil
    }

    fileprivate func fail(_ message: String) {
        show(nil)
        hostError = message
    }
}

@MainActor
final class ExtensionService {
    private static let insertTimeout: Duration = .milliseconds(300)
    private static let cleanupPromptTimeout: Duration = .milliseconds(300)
    private static let cleanupStepTimeout: Duration = .milliseconds(300)
    private static let transcribeTimeout: Duration = .seconds(2)
    private static let commandTimeout: Duration = .seconds(10)
    private static let maxRestarts = 3
    private static let watchdogInterval: Duration = .seconds(5)
    private static let pingTimeout: Duration = .seconds(2)
    /// Actions and events that nothing waits for run until they finish. A day stands in for no limit.
    private static let untimed: Duration = .seconds(86_400)
    private static let healthyUptime: Duration = .seconds(60)
    nonisolated private static let audioDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("voz-extension-audio", isDirectory: true)
    nonisolated static let resources = Bundle.main.resourceURL!.appendingPathComponent("Extensions", isDirectory: true)

    private let home = VozHome()
    private let output: TextOutput
    private let toast: ToastController
    private let settings: AppSettings
    private let fileTranscriber: FileTranscriber
    let catalog = ExtensionCatalog()
    private var host: ExtensionHost?
    private var manifest: HostManifest?
    private var restarts = 0
    private var started = ContinuousClock.now
    private var observer: NSObjectProtocol?
    private var reloading: Task<Void, Never>?
    private var reloadRequested = false
    private var generation = UUID()
    private var watchdog: Task<Void, Never>?
    private var watcher: FileWatcher?
    private var loadedExtensionSettings: Data?
    private lazy var hotkeys = ActionHotkeys { [weak self] id in
        guard let action = self?.manifest?.actions.first(where: { $0.id == id }) else { return }
        self?.runAction(action)
    }

    init(output: TextOutput, toast: ToastController, settings: AppSettings, fileTranscriber: FileTranscriber) {
        self.output = output
        self.toast = toast
        self.settings = settings
        self.fileTranscriber = fileTranscriber
        catalog.perform = { [weak self] action in self?.runAction(action) }
    }

    func start() {
        do {
            if FileManager.default.fileExists(atPath: Self.audioDirectory.path) {
                try FileManager.default.removeItem(at: Self.audioDirectory)
            }
        } catch {
            Log.extensions.error("Could not clear extension audio files: \(error.localizedDescription, privacy: .public)")
            toast.show("Could not prepare extensions")
            return
        }
        observer = DistributedNotificationCenter.default().addObserver(forName: VozHome.changedNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.restarts = 0
                self?.reload()
            }
        }
        reload()
    }

    func reload() {
        reloadRequested = true
        guard reloading == nil else { return }
        reloading = Task {
            repeat {
                reloadRequested = false
                await reloadHost()
            } while reloadRequested
            reloading = nil
        }
    }

    private func reloadHost() async {
        generation = UUID()
        watchdog?.cancel()
        hotkeys.unregisterAll()
        await host?.stop()
        host = nil
        manifest = nil
        loadedExtensionSettings = try? home.extensionSettings()
        watch()
        guard home.hasEnabledExtensions else { return catalog.show(nil) }
        do {
            try home.writeAuthoringFiles(from: Self.resources)
            try await launch()
        } catch {
            Log.extensions.error("Extensions failed to start: \(String(describing: error), privacy: .public)")
            Analytics.report(.extensionsStartFailed)
            toast.show("Could not start extensions")
            catalog.fail("Extensions could not start: \(error)")
        }
    }

    func cleanupPrompt(_ prompt: String, app: HostApp) async -> String {
        guard let host, manifest?.subscribes(to: .beforeCleanup) == true else { return prompt }
        return await host.beforeCleanup(prompt: prompt, app: app, timeout: Self.cleanupPromptTimeout)
    }

    func hasSpeechModel(_ id: String) -> Bool {
        manifest?.speechModels.contains { $0.id == id } == true
    }

    func cleanupExtensions(model: String, app: HostApp) -> CleanupExtensions {
        let extensionModel: CleanupExtensions.Model = { [weak self] text, prompt, timeout in
            await self?.host?.clean(model: model, text: text, prompt: prompt, app: app, timeout: timeout)
        }
        let usesExtensionModel = manifest?.cleanupModels.contains { $0.id == model } == true
        return CleanupExtensions(model: usesExtensionModel ? extensionModel : nil) { [weak self] id, text, deadline in
            await self?.runStep(id, text: text, app: app, deadline: deadline) ?? text
        }
    }

    func transcribe(_ samples: [Float], model: String, app: HostApp) async -> String? {
        guard let host, hasSpeechModel(model) else { return nil }
        let file = Self.audioDirectory.appendingPathComponent("segment-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: file) }
        do {
            try await Task.detached { try Self.writeAudio(samples, to: file) }.value
        } catch {
            Log.extensions.error("Segment file write failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        let seconds = Double(samples.count) / RecordingFilter.sampleRate
        return await host.transcribe(model: model, path: file.path, seconds: seconds, app: app, timeout: Self.transcribeTimeout)
    }

    private func runStep(_ id: String, text: String, app: HostApp, deadline: ContinuousClock.Instant) async -> String {
        let timeout = min(Self.cleanupStepTimeout, deadline - .now)
        guard timeout > .zero, let host, manifest?.cleanupSteps.contains(where: { $0.id == id }) == true else { return text }
        return await host.cleanupStep(id, text: text, app: app, timeout: timeout) ?? text
    }

    func prepare(_ text: String, raw: String, app: HostApp) async -> ExtensionDelivery {
        guard let host, let manifest else { return ExtensionDelivery(text: text, command: nil) }
        let match = VoiceCommands.match(text, commands: manifest.commands)
        if let match, match.at == .start { return ExtensionDelivery(text: "", command: match) }
        var delivered = match?.text ?? text
        if manifest.subscribes(to: .beforeInsert), !delivered.isEmpty {
            delivered = await host.beforeInsert(text: delivered, raw: raw, app: app, timeout: Self.insertTimeout)
        }
        return ExtensionDelivery(text: delivered, command: match.map { VoiceCommandMatch(phrase: $0.phrase, at: $0.at, text: delivered) })
    }

    func recorded(_ samples: [Float], app: HostApp) {
        guard let host, manifest?.subscribes(to: .afterRecording) == true else { return }
        let file = Self.audioDirectory.appendingPathComponent("recording-\(UUID().uuidString).wav")
        let seconds = Double(samples.count) / RecordingFilter.sampleRate
        Task.detached {
            defer { try? FileManager.default.removeItem(at: file) }
            do {
                try Self.writeAudio(samples, to: file)
            } catch {
                Log.extensions.error("Recording file write failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            await host.emit(.afterRecording(path: file.path, seconds: seconds), app: app, timeout: Self.untimed)
        }
    }

    nonisolated private static func writeAudio(_ samples: [Float], to file: URL) throws {
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: audioDirectory.path)
        try WAVEncoder.encode(samples, sampleRate: Int(RecordingFilter.sampleRate)).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    func inserted(_ text: String, raw: String, app: HostApp) {
        guard let host, manifest?.subscribes(to: .afterInsert) == true else { return }
        Task { await host.emit(.afterInsert(text: text, raw: raw), app: app, timeout: Self.untimed) }
    }

    var acceptsAudioDrops: Bool {
        manifest?.subscribes(to: .audioDrop) == true
    }

    func dropAudio(_ file: URL) async -> Bool {
        guard let host else { return false }
        return await host.emit(.audioDrop(path: file.path), app: .current, timeout: Self.untimed)
    }

    func run(_ command: VoiceCommandMatch, app: HostApp) {
        guard let host else { return }
        Task {
            let handled = await host.runCommand(command, app: app, timeout: Self.commandTimeout)
            if !handled {
                Log.extensions.error("Voice command was not handled: \(command.phrase, privacy: .public)")
                toast.show("Voice command failed")
            }
        }
    }

    func runAction(_ action: ExtensionAction) {
        guard let host else { return }
        let app = HostApp.current
        Task {
            if await !host.runAction(action.id, app: app, timeout: Self.untimed) { toast.show("\(action.name) failed") }
        }
    }

    private func launch() async throws {
        let generation = generation
        let script = Self.resources.appendingPathComponent("host.ts")
        let host = ExtensionHost(
            launch: .init(bun: try await BunRuntime.ensure(), script: script, home: home, packageDirectories: try home.packageDirectories()),
            onAction: { [weak self] action in
                Task { @MainActor in
                    guard let self, self.generation == generation else { return }
                    await self.perform(action)
                }
            },
            onLog: { message in Log.extensions.notice("\(message, privacy: .public)") },
            onExit: { [weak self] status in
                Task { @MainActor in
                    guard let self, self.generation == generation else { return }
                    self.hostExited(status)
                }
            },
            transcribeFile: { [weak self, fileTranscriber] params in
                guard let model = await self?.settings.localSpeechModel else { throw CancellationError() }
                return try await fileTranscriber.transcribe(URL(fileURLWithPath: params.path), model: model, speakers: params.speakers)
            }
        )
        let manifest = try await host.start()
        for error in manifest.errors { Log.extensions.error("\(error.extension, privacy: .public) failed to load: \(error.message, privacy: .public)") }
        if !manifest.errors.isEmpty { toast.show("Could not load \(manifest.errors.map(\.extension).joined(separator: ", "))") }
        Log.extensions.notice("Extensions loaded: \(manifest.extensions.joined(separator: ", "), privacy: .public)")
        self.host = host
        self.manifest = manifest
        catalog.show(manifest)
        let unusable = hotkeys.register(manifest.actions)
        if !unusable.isEmpty { toast.show("Could not use the hotkey for \(unusable.map(\.name).joined(separator: ", "))") }
        started = .now
        watchdog = Task { [weak self] in await self?.watch(host) }
    }

    private func watch() {
        try? FileManager.default.createDirectory(at: home.extensions, withIntermediateDirectories: true)
        let paths = [home.extensions.path, home.settings.path] + ((try? home.localPackageDirectories()) ?? []).map(\.path)
        watcher = FileWatcher(paths: paths) { [weak self] changed in
            self?.filesChanged(changed)
        }
    }

    private func filesChanged(_ changed: [String]) {
        settings.reloadPipeline()
        let onlySettingsFolder = changed.allSatisfy { URL(fileURLWithPath: $0).deletingLastPathComponent().standardizedFileURL == home.root.standardizedFileURL }
        if onlySettingsFolder, (try? home.extensionSettings()) == loadedExtensionSettings { return }
        restarts = 0
        reload()
    }

    private func watch(_ host: ExtensionHost) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.watchdogInterval)
            guard !Task.isCancelled, self.host === host else { return }
            if await host.ping(timeout: Self.pingTimeout) { continue }
            guard !Task.isCancelled, self.host === host else { return }
            await host.stop()
            hostExited(-1)
            return
        }
    }

    private func perform(_ action: HostAction) async {
        switch action {
        case .insert(let text):
            await output.deliver(text)
        case .press(let key):
            do {
                output.press(try KeyChord(parsing: key))
            } catch {
                Log.extensions.error("Extension pressed an unknown key: \(key, privacy: .public)")
            }
        case .notify(let text):
            toast.show(text)
        }
    }

    private func hostExited(_ status: Int32) {
        watchdog?.cancel()
        hotkeys.unregisterAll()
        host = nil
        manifest = nil
        if ContinuousClock.now - started > Self.healthyUptime { restarts = 0 }
        guard restarts < Self.maxRestarts else {
            Log.extensions.error("Extension host keeps exiting, last status \(status), extensions stay off until the next change")
            Analytics.report(.extensionHostCrashLoop)
            catalog.fail("Extensions keep crashing, so Voz turned them off. Voz tries again when you change an extension.")
            return
        }
        restarts += 1
        Log.extensions.error("Extension host exited with status \(status), restarting")
        reload()
    }
}

@MainActor
final class FileWatcher {
    private static let latency: CFTimeInterval = 0.3

    private let onChange: @MainActor ([String]) -> Void
    private var stream: FSEventStreamRef?

    init(paths: [String], onChange: @escaping @MainActor ([String]) -> Void) {
        self.onChange = onChange
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, eventPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            let changed = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String] ?? []
            MainActor.assumeIsolated { watcher.onChange(Array(changed.prefix(count))) }
        }
        stream = FSEventStreamCreate(nil, callback, &context, paths as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), Self.latency, FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes))
        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    isolated deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
