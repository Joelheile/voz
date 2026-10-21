import Foundation
import VozCore

struct ExtensionDelivery {
    let text: String
    let command: String?
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
    private static let eventTimeout: Duration = .seconds(30)
    private static let healthyUptime: Duration = .seconds(60)
    nonisolated private static let audioDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("voz-extension-audio", isDirectory: true)
    nonisolated static let resources = Bundle.main.resourceURL!.appendingPathComponent("Extensions", isDirectory: true)

    private let home = VozHome()
    private let output: TextOutput
    private let toast: ToastController
    private let settings: AppSettings
    let catalog = ExtensionCatalog()
    private var host: ExtensionHost?
    private var manifest: HostManifest?
    private var restarts = 0
    private var started = ContinuousClock.now
    private var observer: NSObjectProtocol?
    private var reloading: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var watcher: FileWatcher?
    private var loadedExtensionSettings: Data?
    private lazy var hotkeys = ActionHotkeys { [weak self] id in
        guard let action = self?.manifest?.actions.first(where: { $0.id == id }) else { return }
        self?.runAction(action)
    }

    init(output: TextOutput, toast: ToastController, settings: AppSettings) {
        self.output = output
        self.toast = toast
        self.settings = settings
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
        reloading = Task { [previous = reloading] in
            await previous?.value
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
                toast.show("Could not start extensions")
                catalog.fail("Extensions could not start: \(error)")
            }
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
        let match = VoiceCommands.match(text, phrases: manifest.commands.map(\.phrase))
        let dictated = match?.leadingText ?? text
        guard manifest.subscribes(to: .beforeInsert), !dictated.isEmpty else { return ExtensionDelivery(text: dictated, command: match?.phrase) }
        let transformed = await host.beforeInsert(text: dictated, raw: raw, app: app, timeout: Self.insertTimeout)
        return ExtensionDelivery(text: transformed, command: match?.phrase)
    }

    func recorded(_ samples: [Float], app: HostApp) {
        guard let host, manifest?.subscribes(to: .recording) == true else { return }
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
            await host.emit(.recording(path: file.path, seconds: seconds), app: app, timeout: Self.eventTimeout)
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
        Task { await host.emit(.afterInsert(text: text, raw: raw), app: app, timeout: Self.eventTimeout) }
    }

    func run(_ command: String, text: String, app: HostApp) {
        guard let host else { return }
        Task {
            let handled = await host.runCommand(phrase: command, text: text, app: app, timeout: Self.commandTimeout)
            if !handled { Log.extensions.error("Voice command was not handled: \(command, privacy: .public)") }
        }
    }

    func runAction(_ action: ExtensionAction) {
        guard let host else { return }
        let app = HostApp.current
        Task {
            if await !host.runAction(action.id, app: app, timeout: Self.commandTimeout) { toast.show("\(action.name) failed") }
        }
    }

    private func launch() async throws {
        let script = Self.resources.appendingPathComponent("host.ts")
        let host = ExtensionHost(
            launch: .init(bun: try await BunRuntime.ensure(), script: script, home: home, packageDirectories: try home.packageDirectories()),
            onAction: { [weak self] action in
                Task { @MainActor in await self?.perform(action) }
            },
            onLog: { message in Log.extensions.notice("\(message, privacy: .public)") },
            onExit: { [weak self] status in
                Task { @MainActor in self?.hostExited(status) }
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
            catalog.fail("Extensions keep crashing, so Voz turned them off. Voz tries again when you change an extension.")
            return
        }
        restarts += 1
        Log.extensions.error("Extension host exited with status \(status), restarting")
        reload()
    }
}
