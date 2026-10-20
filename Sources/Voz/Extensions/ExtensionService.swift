import Foundation
import VozCore

struct ExtensionDelivery {
    let text: String
    let command: String?
}

@MainActor
final class ExtensionService {
    private static let insertTimeout: Duration = .milliseconds(300)
    private static let cleanupPromptTimeout: Duration = .milliseconds(300)
    private static let commandTimeout: Duration = .seconds(10)
    private static let maxRestarts = 3
    private static let watchdogInterval: Duration = .seconds(5)
    private static let pingTimeout: Duration = .seconds(2)
    private static let eventTimeout: Duration = .seconds(30)
    private static let healthyUptime: Duration = .seconds(60)
    nonisolated static let resources = Bundle.main.resourceURL!.appendingPathComponent("Extensions", isDirectory: true)

    private let home = VozHome()
    private let output: TextOutput
    private let toast: ToastController
    private var host: ExtensionHost?
    private var manifest: HostManifest?
    private var restarts = 0
    private var started = ContinuousClock.now
    private var observer: NSObjectProtocol?
    private var reloading: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var watcher: FileWatcher?

    init(output: TextOutput, toast: ToastController) {
        self.output = output
        self.toast = toast
    }

    func start() {
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
            await host?.stop()
            host = nil
            manifest = nil
            watch()
            guard home.hasExtensions else { return }
            do {
                try home.writeAuthoringFiles(from: Self.resources)
                try await launch()
            } catch {
                Log.extensions.error("Extensions failed to start: \(String(describing: error), privacy: .public)")
                toast.show("Could not start extensions")
            }
        }
    }

    func cleanupPrompt(_ prompt: String, app: HostApp) async -> String {
        guard let host, manifest?.subscribes(to: .beforeCleanup) == true else { return prompt }
        return await host.beforeCleanup(prompt: prompt, app: app, timeout: Self.cleanupPromptTimeout)
    }

    func prepare(_ text: String, raw: String, app: HostApp) async -> ExtensionDelivery {
        guard let host, let manifest else { return ExtensionDelivery(text: text, command: nil) }
        let match = VoiceCommands.match(text, phrases: manifest.commands)
        let dictated = match?.leadingText ?? text
        guard manifest.subscribes(to: .beforeInsert), !dictated.isEmpty else { return ExtensionDelivery(text: dictated, command: match?.phrase) }
        let transformed = await host.beforeInsert(text: dictated, raw: raw, app: app, timeout: Self.insertTimeout)
        return ExtensionDelivery(text: transformed, command: match?.phrase)
    }

    func recorded(_ samples: [Float], app: HostApp) {
        guard let host, manifest?.subscribes(to: .recording) == true else { return }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("voz-recording-\(UUID().uuidString).wav")
        let seconds = Double(samples.count) / RecordingFilter.sampleRate
        Task.detached {
            do {
                try WAVEncoder.encode(samples, sampleRate: Int(RecordingFilter.sampleRate)).write(to: file)
            } catch {
                Log.extensions.error("Recording file write failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            await host.emit(.recording(path: file.path, seconds: seconds), app: app, timeout: Self.eventTimeout)
            try? FileManager.default.removeItem(at: file)
        }
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
        started = .now
        watchdog = Task { [weak self] in await self?.watch(host) }
    }

    private func watch() {
        try? FileManager.default.createDirectory(at: home.extensions, withIntermediateDirectories: true)
        let paths = [home.extensions.path, home.settings.path] + ((try? home.localPackageDirectories()) ?? []).map(\.path)
        watcher = FileWatcher(paths: paths) { [weak self] in
            self?.restarts = 0
            self?.reload()
        }
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
        host = nil
        manifest = nil
        if ContinuousClock.now - started > Self.healthyUptime { restarts = 0 }
        guard restarts < Self.maxRestarts else {
            Log.extensions.error("Extension host keeps exiting, last status \(status), extensions stay off until the next change")
            return
        }
        restarts += 1
        Log.extensions.error("Extension host exited with status \(status), restarting")
        reload()
    }
}
