import Foundation
import VozCore

struct ExtensionDelivery {
    let text: String
    let command: String?
}

@MainActor
final class ExtensionService {
    private static let insertTimeout: Duration = .milliseconds(300)
    private static let commandTimeout: Duration = .seconds(10)
    private static let maxRestarts = 3
    private static let watchdogInterval: Duration = .seconds(5)
    private static let pingTimeout: Duration = .seconds(2)

    private let home = VozHome()
    private let output: TextOutput
    private var host: ExtensionHost?
    private var commands: [String] = []
    private var restarts = 0
    private var observer: NSObjectProtocol?
    private var reloading: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var watcher: FileWatcher?

    init(output: TextOutput) {
        self.output = output
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
            commands = []
            watch()
            guard home.hasExtensions else { return }
            do {
                try await launch()
            } catch {
                Log.extensions.error("Extensions failed to start: \(String(describing: error), privacy: .public)")
            }
        }
    }

    func prepare(_ text: String, raw: String, app: FrontApp) async -> ExtensionDelivery {
        guard let host else { return ExtensionDelivery(text: text, command: nil) }
        let match = VoiceCommands.match(text, phrases: commands)
        let dictated = match?.leadingText ?? text
        let transformed = dictated.isEmpty ? "" : await host.beforeInsert(text: dictated, raw: raw, app: app.hostApp, timeout: Self.insertTimeout)
        return ExtensionDelivery(text: transformed, command: match?.phrase)
    }

    func run(_ command: String, text: String, app: FrontApp) {
        guard let host else { return }
        Task {
            let handled = await host.runCommand(phrase: command, text: text, app: app.hostApp, timeout: Self.commandTimeout)
            if !handled { Log.extensions.error("Voice command was not handled: \(command, privacy: .public)") }
        }
    }

    private func launch() async throws {
        guard let script = Bundle.main.url(forResource: "host", withExtension: "ts", subdirectory: "Extensions") else {
            Log.extensions.error("Extension host script missing from app bundle")
            return
        }
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
        for error in manifest.errors { Log.extensions.error("Extension failed to load: \(error, privacy: .public)") }
        Log.extensions.notice("Extensions loaded: \(manifest.extensions.joined(separator: ", "), privacy: .public)")
        self.host = host
        commands = manifest.commands
        watchdog = Task { [weak self] in await self?.watch(host) }
    }

    private func watch() {
        try? FileManager.default.createDirectory(at: home.extensions, withIntermediateDirectories: true)
        let paths = [home.extensions.path] + ((try? home.localPackageDirectories()) ?? []).map(\.path)
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
        }
    }

    private func hostExited(_ status: Int32) {
        watchdog?.cancel()
        host = nil
        commands = []
        guard restarts < Self.maxRestarts else {
            Log.extensions.error("Extension host keeps exiting, last status \(status), extensions stay off until the next change")
            return
        }
        restarts += 1
        Log.extensions.error("Extension host exited with status \(status), restarting")
        reload()
    }
}

private extension FrontApp {
    var hostApp: HostApp { HostApp(bundleID: bundleID, name: name) }
}
