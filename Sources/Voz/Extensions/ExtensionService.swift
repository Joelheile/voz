import AppKit
import CoreServices

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
    @Published fileprivate(set) var tools: [ExtensionTool] = []
    @Published fileprivate(set) var activities: [ExtensionActivity] = []
    @Published fileprivate(set) var settings: [ExtensionSettings] = []
    @Published fileprivate(set) var lists: [SettingsList] = []
    @Published fileprivate(set) var hostError: String?
    /// Extensions whose package.json asks to read the screen
    @Published fileprivate(set) var screenReaders: [String] = []
    fileprivate var perform: (ExtensionAction) -> Void = { _ in }
    fileprivate var performTool: (ExtensionTool, [String: JSONValue]) async throws -> JSONValue = { tool, _ in
        throw ControlError.failed("Extensions are not running, so \(tool.id) can't run.")
    }
    fileprivate var performList: (SettingsList, String?) async throws -> [SettingsListItem] = { list, _ in
        throw ControlError.failed("Extensions are not running, so \(list.title) can't load.")
    }
    fileprivate var performStop: (ExtensionActivity) -> Void = { _ in }
    fileprivate var performOpen: (ExtensionActivity) -> Void = { _ in }

    init(actions: [ExtensionAction] = [], activities: [ExtensionActivity] = []) {
        self.actions = actions
        self.activities = activities
    }

    func run(_ action: ExtensionAction) {
        perform(action)
    }

    func call(_ tool: ExtensionTool, input: [String: JSONValue]) async throws -> JSONValue {
        try await performTool(tool, input)
    }

    /// The rows of `list`, after removing the row `remove` when given
    func items(_ list: SettingsList, removing remove: String? = nil) async throws -> [SettingsListItem] {
        try await performList(list, remove)
    }

    func lists(for name: String) -> [SettingsList] {
        lists.filter { Self.belongs($0.extension, to: name) }
    }

    func tools(for name: String) -> [ExtensionTool] {
        tools.filter { Self.belongs($0.extension, to: name) }
    }

    func stop(_ activity: ExtensionActivity) {
        performStop(activity)
    }

    func open(_ activity: ExtensionActivity) {
        performOpen(activity)
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

    func readsScreen(_ name: String) -> Bool {
        screenReaders.contains { Self.belongs($0, to: name) }
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
        tools = manifest?.tools ?? []
        settings = manifest?.settings ?? []
        lists = manifest?.lists ?? []
        screenReaders = manifest?.screen ?? []
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
    private static let cleanupPlanTimeout: Duration = .milliseconds(300)
    private static let cleanupStepTimeout: Duration = .milliseconds(300)
    private static let transcribeTimeout: Duration = .seconds(2)
    private static let commandTimeout: Duration = .seconds(10)
    /// Agents and scripts wait on a tool, so a hung one must fail instead of holding them forever
    static let toolTimeout: Duration = .seconds(60)
    private static let maxRestarts = 3
    private static let watchdogInterval: Duration = .seconds(5)
    private static let pingTimeout: Duration = .seconds(2)
    /// Actions and events that nothing waits for run until they finish. A day stands in for no limit.
    private static let untimed: Duration = .seconds(86_400)
    nonisolated private static let historyLimit = 20
    /// A draft that replaces a dictation this recent is linked to it
    private static let draftDictationWindow: TimeInterval = 600
    private static let healthyUptime: Duration = .seconds(60)
    nonisolated private static let audioDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("voz-extension-audio", isDirectory: true)
    nonisolated static let resources = Bundle.main.resourceURL!.appendingPathComponent("Extensions", isDirectory: true)

    private let home = VozHome()
    private let output: TextOutput
    private let toast: ToastController
    private let settings: AppSettings
    private let fileTranscriber: FileTranscriber
    private let live: LiveSessions
    private let note: NoteController
    private let asker = AskController()
    var isAsking: Bool { asker.isOpen }
    private let drafts: DraftStore
    private let draftWatcher: DraftWatcher
    let catalog = ExtensionCatalog()
    var liveStatus: LiveStatus { live.status }
    var onWorking: () -> Void = {}
    var onExtensionUsed: (_ name: String) -> Void = { _ in }
    var onWorked: (_ succeeded: Bool) -> Void = { _ in }
    var onFileProgress: (Double) -> Void = { _ in }
    var onHistory: (ExtensionHistoryEntry) -> Void = { _ in }
    private var runningDrops = 0
    private var fileTranscriptions: [UUID: Task<FileTranscript, any Error>] = [:]
    /// Work extensions run inside `ctx.busy`, which you can cancel from the notch
    private var busyWork: Set<String> = []
    private var host: ExtensionHost?
    private var manifest: HostManifest?
    private var restarts = 0
    private var started = ContinuousClock.now
    private var observer: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?
    private var reloading: Task<Void, Never>?
    private var reloadRequested = false
    private var generation = UUID()
    private var watchdog: Task<Void, Never>?
    private var watcher: FileWatcher?
    private var loadedExtensionSettings: Data?
    private lazy var hotkeys = ActionHotkeys(dictationKey: { [unowned self] in settings.hotkey }) { [weak self] ids in
        guard let self else { return }
        let candidates = ids.compactMap { id in self.catalog.actions.first { $0.id == id } }
        let hasSelection = candidates.contains { $0.when != nil }
            && NSWorkspace.shared.frontmostApplication.flatMap { FieldReader.selection(pid: $0.processIdentifier) }.map { !$0.text.isEmpty } == true
        if let action = ExtensionAction.pick(candidates, hasSelection: hasSelection) { pickModelThenRun(action) }
    }

    init(output: TextOutput, toast: ToastController, settings: AppSettings, fileTranscriber: FileTranscriber, drafts: DraftStore) {
        self.output = output
        self.drafts = drafts
        draftWatcher = DraftWatcher(store: drafts)
        self.toast = toast
        self.settings = settings
        self.fileTranscriber = fileTranscriber
        live = LiveSessions(transcriber: fileTranscriber.transcriber, vocabulary: fileTranscriber.vocabulary, settings: settings)
        note = NoteController(live: live.status)
        catalog.perform = { [weak self] action in self?.runAction(action) }
        catalog.performTool = { [weak self] tool, input in
            guard let host = self?.host else { throw ControlError.failed("Extensions are not running, so \(tool.id) can't run.") }
            self?.onExtensionUsed(tool.extension)
            return try await host.runTool(tool.id, input: input, app: await HostApp.front().value, timeout: Self.toolTimeout)
        }
        catalog.performList = { [weak self] list, remove in
            guard let host = self?.host else { throw ControlError.failed("Extensions are not running, so \(list.title) can't load.") }
            return try await host.list(list.id, remove: remove, timeout: Self.toolTimeout)
        }
        catalog.performStop = { [weak self] activity in self?.stopActivity(activity) }
        catalog.performOpen = { [weak self] activity in self?.openActivity(activity) }
        note.onChange = { [weak self] id, text in self?.noteChanged(id, text: text) }
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
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                guard self?.host != nil else { return }
                FocusedWebsite.enableWebAccessibility(in: app)
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
        endActivities()
        loadedExtensionSettings = try? home.extensionSettings()
        watch()
        guard home.hasEnabledExtensions else { return catalog.show(nil) }
        do {
            try home.writeAuthoringFiles(from: Self.resources)
            try await launch()
        } catch {
            Log.extensions.error("Extensions failed to start: \(String(describing: error), privacy: .public)")
            Analytics.report(.extensionsStartFailed, cause: error)
            toast.show("Could not start extensions")
            catalog.fail("Extensions could not start: \(error)")
        }
    }

    func cleanupPlan(_ plan: CleanupPlan, app: HostApp) async -> CleanupPlan {
        guard let host, manifest?.subscribes(to: .beforeCleanup) == true else { return plan }
        return await host.beforeCleanup(plan, app: app, timeout: Self.cleanupPlanTimeout)
    }

    func hasSpeechModel(_ id: String) -> Bool {
        manifest?.speechModels.contains { $0.id == id } == true
    }

    func cleanupExtensions(model: String, app: Task<HostApp, Never>) -> CleanupExtensions {
        let extensionModel: CleanupExtensions.Model = { [weak self] text, prompt, timeout in
            await self?.host?.clean(model: model, text: text, prompt: prompt, app: await app.value, timeout: timeout)
        }
        let usesExtensionModel = manifest?.cleanupModels.contains { $0.id == model } == true
        return CleanupExtensions(model: usesExtensionModel ? extensionModel : nil) { [weak self] id, text, deadline in
            await self?.runStep(id, text: text, app: await app.value, deadline: deadline) ?? text
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
        if let match, match.at != .end { return ExtensionDelivery(text: "", command: match) }
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
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: AppStorage.directoryPermissions])
        try FileManager.default.setAttributes([.posixPermissions: AppStorage.directoryPermissions], ofItemAtPath: audioDirectory.path)
        try WAVEncoder.encode(samples, sampleRate: Int(RecordingFilter.sampleRate)).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: AppStorage.filePermissions], ofItemAtPath: file.path)
    }

    /// The app the user types in. Voz's own panels never count, because Accessibility can't read Voz from inside Voz.
    private static func frontTarget() -> (pid: pid_t, app: NSRunningApplication)? {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        return (app.processIdentifier, app)
    }

    private static func frontTargetPID() -> pid_t? {
        frontTarget()?.pid
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
        runningDrops += 1
        defer { runningDrops -= 1 }
        return await host.emit(.audioDrop(path: file.path), app: await HostApp.front().value, timeout: Self.untimed)
    }

    func run(_ command: VoiceCommandMatch, app: HostApp) {
        guard let host else { return }
        if let source = catalog.commands.first(where: { $0.phrase == command.phrase && $0.at == command.at }) { onExtensionUsed(source.extension) }
        Task {
            let handled = await host.runCommand(command, app: app, timeout: Self.commandTimeout)
            if !handled {
                Log.extensions.error("Voice command was not handled: \(command.phrase, privacy: .public)")
                toast.show("Voice command failed")
            }
        }
    }

    /// Until you pick an AI model, a hotkey asks which one first, leading with ChatGPT
    private func pickModelThenRun(_ action: ExtensionAction) {
        guard !settings.hasPickedAIModel else { return runAction(action) }
        Task {
            guard let answer = await asker.ask(AIModels.pickCard) else { return }
            do {
                if try await AIModels.pick(answer, settings) { return runAction(action) }
                toast.show("Signed in. Press \(action.hotkeyLabel ?? "the hotkey") again")
            } catch {
                toast.show(error.localizedDescription)
            }
        }
    }

    func runAction(_ action: ExtensionAction) {
        guard let host else { return }
        onExtensionUsed(action.extension)
        let app = HostApp.front()
        Task {
            let app = await app.value
            if await !host.runAction(action.id, app: app, timeout: Self.untimed) { toast.show("\(action.name) failed") }
        }
    }

    private func stopActivity(_ activity: ExtensionActivity) {
        guard let host else { return }
        let app = HostApp.front()
        Task {
            let app = await app.value
            if await !host.stopActivity(activity.id, app: app, timeout: Self.untimed) { toast.show("Could not stop \(activity.title)") }
        }
    }

    private func openActivity(_ activity: ExtensionActivity) {
        guard let host, activity.openable else { return }
        let app = HostApp.front()
        Task {
            let app = await app.value
            if await !host.openActivity(activity.id, app: app, timeout: Self.untimed) { toast.show("Could not open \(activity.title)") }
        }
    }

    private func noteChanged(_ id: String, text: String) {
        guard let host else { return }
        Task { _ = await host.noteChanged(id, text: text, timeout: Self.untimed) }
    }

    private func startLive(_ params: LiveStartParams, onTranscript: @escaping @Sendable (FileTranscript) async -> Void) async throws {
        guard catalog.activities.contains(where: { $0.id == params.activity }) else { throw LiveSessionError.unknown(params.session) }
        try await live.start(params, onTranscript: onTranscript)
    }

    private func endActivities() {
        catalog.activities = []
        live.stopAll()
        note.close()
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
            onLog: { message in
                Log.extensions.notice("\(message, privacy: .public)")
                DebugLog.shared.write("extension", ["message": message])
            },
            onExit: { [weak self] status in
                Task { @MainActor in
                    guard let self, self.generation == generation else { return }
                    self.hostExited(status)
                }
            },
            transcribeFile: { [weak self] params in
                guard let self else { throw CancellationError() }
                return try await self.transcribe(params)
            },
            startLive: { [weak self] params, onTranscript in
                guard let self else { throw CancellationError() }
                try await self.startLive(params, onTranscript: onTranscript)
            },
            stopLive: { [weak self] params in
                guard let self else { throw CancellationError() }
                return try await self.live.stop(params.session)
            },
            ask: { [weak self] params in await self?.asker.ask(params) },
            field: { [drafts] in
                guard let (pid, app) = await Self.frontTarget() else { return nil }
                return await Task.detached {
                    guard var field = FieldReader.read(pid: pid) else { return nil }
                    if let thread = try? drafts.thread(app: app.bundleIdentifier, window: field.window, appName: app.localizedName) {
                        field.thread = FieldThread(id: thread.id, title: thread.title)
                    }
                    return field
                }.value
            },
            select: { range in
                guard let pid = await Self.frontTargetPID() else { return false }
                return await Task.detached { FieldReader.select(range, pid: pid) }.value
            },
            history: { [drafts] params in
                let thread = params.thread.map(UUID.init(uuidString:))
                if case .some(nil) = thread { return [] }
                return try drafts.written(thread: thread ?? nil, source: params.source, limit: params.limit ?? Self.historyLimit)
            },
            screen: { [drafts] in
                guard let (pid, app) = await Self.frontTarget(), let bundleID = app.bundleIdentifier,
                      !ScreenText.excluded.contains(bundleID) else { return nil }
                let name = app.localizedName ?? bundleID
                return await Task.detached {
                    guard let seen = FieldReader.windowText(pid: pid, limit: ScreenText.maxText),
                          !ScreenText.isPrivate(app: bundleID, window: seen.window, toolbar: seen.toolbar) else { return nil }
                    let thread = try? drafts.thread(app: bundleID, window: seen.window, appName: name)
                    return ScreenText(app: name, window: seen.window, thread: thread?.id, text: Redaction.redact(seen.text))
                }.value
            }
        )
        let manifest = try await host.start()
        for error in manifest.errors { Log.extensions.error("\(error.extension, privacy: .public) failed to load: \(error.message, privacy: .public)") }
        if !manifest.errors.isEmpty { toast.show("Could not load \(manifest.errors.map(\.extension).joined(separator: ", "))") }
        Log.extensions.notice("Extensions loaded: \(manifest.extensions.joined(separator: ", "), privacy: .public)")
        self.host = host
        self.manifest = manifest
        NSWorkspace.shared.runningApplications.forEach(FocusedWebsite.enableWebAccessibility(in:))
        catalog.show(manifest)
        show(manifest.actions)
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

    func cancelWork() {
        for task in fileTranscriptions.values { task.cancel() }
        let cancelled = busyWork
        busyWork = []
        guard let host else { return }
        for id in cancelled { Task { _ = await host.cancelBusy(id, timeout: Self.pingTimeout) } }
    }

    private func transcribe(_ params: TranscribeFileParams) async throws -> FileTranscript {
        let progress: @Sendable (Double) -> Void = { fraction in
            Task { @MainActor [weak self] in self?.onFileProgress(fraction) }
        }
        let transcribe = { [fileTranscriber, model = settings.localSpeechModel, includesText = settings.logIncludesText] in
            let started = ContinuousClock.now
            var fields: [String: Any] = ["model": model.rawValue, "speakers_requested": params.speakers]
            do {
                let transcript = try await fileTranscriber.transcribe(URL(fileURLWithPath: params.path), model: model, speakers: params.speakers, progress: progress)
                fields.merge(["outcome": "transcribed", "audio_s": transcript.seconds, "speakers": transcript.speakers, "ms": (ContinuousClock.now - started).wholeMilliseconds]) { $1 }
                if includesText { fields["text"] = transcript.text }
                DebugLog.shared.write("file", fields)
                return transcript
            } catch {
                let outcome = error is CancellationError ? "cancelled" : "failed"
                fields.merge(["outcome": outcome, "error": error.localizedDescription, "ms": (ContinuousClock.now - started).wholeMilliseconds]) { $1 }
                DebugLog.shared.write("file", fields)
                throw error
            }
        }
        guard runningDrops == 0 else { return try await cancellable(transcribe) }
        onWorking()
        do {
            let transcript = try await cancellable(transcribe)
            onWorked(true)
            return transcript
        } catch {
            onWorked(false)
            throw error
        }
    }

    private func cancellable(_ work: @escaping () async throws -> FileTranscript) async throws -> FileTranscript {
        let id = UUID()
        let task = Task { try await work() }
        fileTranscriptions[id] = task
        defer { fileTranscriptions[id] = nil }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    private func perform(_ action: HostAction) async {
        switch action {
        case .insert(let insertion):
            await insert(insertion)
        case .press(let key):
            do {
                output.press(try KeyChord(parsing: key))
            } catch {
                Log.extensions.error("Extension pressed an unknown key: \(key, privacy: .public)")
            }
        case .notify(let text):
            toast.show(text)
        case .startActivity(let activity):
            catalog.activities.append(activity)
        case .endActivity(let id):
            catalog.activities.removeAll { $0.id == id }
            live.endActivity(id)
        case .stopActivity(let id):
            if let activity = catalog.activities.first(where: { $0.id == id && $0.stoppable }) { stopActivity(activity) }
        case .openNote(let opened):
            // A note that opens with a running activity, such as notes for a meeting, waits under the notch
            note.show(opened, quietly: !catalog.activities.isEmpty)
        case .closeNote(let id):
            note.close(id)
        case .addHistory(let entry):
            onHistory(entry)
        case .actions(let actions):
            show(actions)
        case .busy(let id):
            busyWork.insert(id)
            if busyWork.count == 1 { onWorking() }
        case .idle(let id, let succeeded):
            guard busyWork.remove(id) != nil, busyWork.isEmpty else { return }
            onWorked(succeeded)
        }
    }

    /// Saves what an extension inserts as a draft, with the text it replaced, then watches what you do with it
    private func insert(_ insertion: Insertion) async {
        guard let source = insertion.source, !insertion.text.isEmpty, let (pid, app) = Self.frontTarget() else {
            await output.deliver(insertion.text)
            return
        }
        let before = await Task.detached { FieldReader.selection(pid: pid) }.value
        await output.deliver(insertion.text)
        let draft: DraftRecord
        do {
            let thread = try drafts.thread(app: app.bundleIdentifier, window: before?.window, appName: app.localizedName)
            let input = before?.text ?? ""
            draft = DraftRecord(
                source: source,
                threadID: thread?.id,
                transcriptID: try drafts.transcriptID(replacedBy: input, since: Date().addingTimeInterval(-Self.draftDictationWindow)),
                instruction: insertion.instruction,
                input: input,
                output: insertion.text
            )
            try drafts.insert(draft)
        } catch {
            Log.extensions.error("Could not save a draft: \(error.localizedDescription, privacy: .public)")
            return
        }
        draftWatcher.watch(draft, pid: pid)
    }

    private func show(_ actions: [ExtensionAction]) {
        catalog.actions = actions
        let unusable = hotkeys.register(actions)
        if !unusable.isEmpty { toast.show("Could not use the hotkey for \(unusable.map(\.name).joined(separator: ", "))") }
    }

    private func hostExited(_ status: Int32) {
        watchdog?.cancel()
        asker.close()
        hotkeys.unregisterAll()
        if !busyWork.isEmpty {
            busyWork = []
            onWorked(false)
        }
        host = nil
        manifest = nil
        endActivities()
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
