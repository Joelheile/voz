import AppKit
import Combine
import VozCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let modelStatus = ModelStatus()
    private let installID = InstallID()
    private lazy var analytics = Analytics(enabled: settings.analyticsEnabled, installID: installID.value)
    private let history = AppDelegate.openHistory()
    private lazy var transcriber = Transcriber { [modelStatus] mode, state in
        DispatchQueue.main.async { MainActor.assumeIsolated { modelStatus.update(mode, state) } }
    }
    private lazy var output = TextOutput(settings: settings)
    private let cleaner = TextCleaner()
    private let toast = ToastController()
    private lazy var extensions = ExtensionService(output: output, toast: toast, settings: settings)
    private var vocabularyWords: [String] = []
    private lazy var dictation = Dictation(
        pipeline: DictationPipeline(
            engine: SpeechEngine(parakeet: transcriber),
            cleaner: cleaner,
            settings: settings,
            history: history,
            output: output,
            editObserver: EditObserver(vocabulary: history.vocabulary),
            analytics: analytics,
            extensions: extensions
        ),
        settings: settings,
        output: output,
        analytics: analytics
    )
    private var cancellables: Set<AnyCancellable> = []
    private lazy var historyModel = HistoryModel(store: history)
    private lazy var statsModel = StatsModel(store: history)
    private lazy var vocabularyModel = VocabularyModel(store: history.vocabulary, analytics: analytics)
    private lazy var setupModel = SetupModel(analytics: analytics)
    private lazy var extensionsModel = ExtensionsModel()
    private var statusItemController: StatusItemController?
    private var hotkeyMonitor: HotkeyMonitor?
    private var quitRequested = false
    private let indicator = IndicatorController()
    private lazy var updater = Updater(settings: settings)

    func applicationDidFinishLaunching(_ notification: Notification) {
        dictation.recoverFromPreviousRun()
        extensions.start()
        let statusItemController = StatusItemController(
            dictation: dictation,
            sources: PopoverSources(
                settings: settings,
                modelStatus: modelStatus,
                history: historyModel,
                stats: statsModel,
                vocabulary: vocabularyModel,
                setup: setupModel,
                extensions: extensionsModel,
                catalog: extensions.catalog
            ),
            analytics: analytics,
            checkForUpdates: { [weak self] in self?.updater.checkForUpdates() },
            finishSetup: { [weak self] in self?.finishSetup() },
            quit: { [weak self] in self?.quitFromMenu() }
        )
        self.statusItemController = statusItemController
        dictation.onChange = { [weak self] in
            guard let self else { return }
            self.statusItemController?.dictationChanged()
            self.indicator.sync(phase: self.dictation.phase)
        }
        hotkeyMonitor = HotkeyMonitor(
            hotkey: settings.hotkey,
            holdToTalk: settings.holdToTalk,
            isRecording: { [weak self] in self?.dictation.isRecording ?? false },
            onAction: { [weak self] action in
                guard let self, !self.settings.isCapturingHotkey else { return }
                self.dictation.handle(action)
            }
        )

        indicator.attach(to: dictation)
        observeWake()
        OpenRequest.observe { [weak self] in self?.statusItemController?.open() }
        observeSettings()
        observeVocabulary()
        if settings.onboardingCompleted {
            Task {
                await Permissions.requestMicrophone()
                dictation.prepareRecorder()
            }
            warmUpModel(settings.localSpeechModel)
            if !Permissions.accessibilityGranted {
                Permissions.promptForAccessibility()
            }
        } else {
            statusItemController.open()
        }
        hotkeyMonitor?.startHealthChecks()
        let launch = LaunchVersion.record(SystemContext.appVersion, in: .standard)
        if let previous = launch.updatedFrom {
            analytics.capture(.updateInstalled(from: previous, to: launch.current, channel: UpdateChannel(version: launch.current)))
        }
        let ping: VersionPing? = installID.isNew ? .install : launch.updatedFrom.map { _ in .update }
        if settings.versionPingEnabled, let ping {
            VersionPinger.send(ping, version: launch.current)
        }
        updater.start()
        analytics.capture(installID.isNew ? .appInstalled : .appLaunched)
        manageLaunchAgent()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let name = urls.lazy.compactMap(ExtensionLink.packageName(in:)).first else { return }
        statusItemController?.open(.extensions)
        Task { await extensionsModel.reveal(name) }
    }

    private func manageLaunchAgent() {
        guard settings.launchAtLogin else {
            LaunchAgent.unregisterIfRegistered()
            return openIfUserLaunched()
        }
        Task {
            guard await LaunchAgent.handOver() else { return openIfUserLaunched() }
            OpenRequest.deferToNextLaunch()
            NSApp.perform(#selector(NSApplication.terminate(_:)), with: nil, afterDelay: 0)
        }
    }

    private func openIfUserLaunched() {
        if OpenRequest.takePending() || !LaunchAgent.launchedByLaunchd {
            statusItemController?.open()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusItemController?.open()
        return false
    }

    private func quitFromMenu() {
        quitRequested = true
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if quitRequested { LaunchAgent.bootOut() }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard settings.analyticsEnabled else { return .terminateNow }
        analytics.flush()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private static func openHistory() -> HistoryStore {
        do {
            let path = try AppStorage.directory().appendingPathComponent("history.sqlite").path
            let store = try HistoryStore(path: path)
            try AppStorage.restrict(fileAt: path)
            return store
        } catch {
            fatalError("History store failed to open: \(error)")
        }
    }

    private func observeSettings() {
        settings.$hotkey.combineLatest(settings.$holdToTalk)
            .dropFirst()
            .sink { [weak self] hotkey, holdToTalk in
                self?.hotkeyMonitor?.configure(hotkey: hotkey, holdToTalk: holdToTalk)
            }
            .store(in: &cancellables)
        settings.$launchAtLogin
            .dropFirst()
            .sink { [weak self] _ in self?.manageLaunchAgent() }
            .store(in: &cancellables)
        settings.$analyticsEnabled
            .dropFirst()
            .sink { [weak self] enabled in self?.analytics.setEnabled(enabled) }
            .store(in: &cancellables)
        settings.$speechModel
            .map { SpeechModel(rawValue: $0) ?? .parakeetUltra }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] model in
                guard let self, self.settings.onboardingCompleted else { return }
                self.warmUpModel(model)
            }
            .store(in: &cancellables)
        settings.$cleanupPrompt
            .dropFirst()
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] prompt in
                guard let self else { return }
                self.cleaner.prewarm(prompt: prompt, vocabulary: self.vocabularyWords)
            }
            .store(in: &cancellables)
    }

    private func observeVocabulary() {
        history.vocabulary.observe()
            .map { $0.words.map(\.word).sorted() }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case let .failure(error) = completion {
                        Log.app.error("Vocabulary observation failed: \(error.localizedDescription, privacy: .private)")
                    }
                },
                receiveValue: { [weak self] _ in self?.syncVocabulary() }
            )
            .store(in: &cancellables)
    }

    private func syncVocabulary() {
        let words: [String]
        do {
            words = try history.vocabulary.words()
        } catch {
            Log.app.error("Vocabulary read failed: \(error.localizedDescription, privacy: .private)")
            return
        }
        vocabularyWords = words
        cleaner.prewarm(prompt: settings.cleanupPrompt, vocabulary: words)
        Task {
            do {
                try await transcriber.prepareVocabulary(words)
            } catch {
                Log.app.error("Vocabulary boosting setup failed: \(error.localizedDescription, privacy: .private)")
            }
        }
    }

    private func finishSetup() {
        setupModel.reportPermissions()
        settings.onboardingCompleted = true
        warmUpModel(settings.localSpeechModel)
    }

    private func warmUpModel(_ model: SpeechModel) {
        let wasDownloaded = model.isDownloaded
        Task {
            let started = Date()
            do {
                if model != .appleSpeech { try await transcriber.prepare(model) }
                await transcriber.removeUnusedModels(keeping: model)
                let seconds = Date().timeIntervalSince(started)
                Log.app.notice("Model \(model.rawValue) ready in \(seconds, format: .fixed(precision: 1))s")
                reportModelReady(model, wasDownloaded: wasDownloaded, seconds: seconds)
            } catch {
                Log.app.error("Model load failed: \(error.localizedDescription, privacy: .private)")
                if !wasDownloaded {
                    analytics.capture(.modelDownload(model: model, seconds: Int(Date().timeIntervalSince(started)), success: false, bytes: 0))
                }
            }
        }
    }

    private func reportModelReady(_ model: SpeechModel, wasDownloaded: Bool, seconds: Double) {
        guard !wasDownloaded else {
            return analytics.capture(.modelLoad(model: model, coldMs: Int(seconds * 1000)))
        }
        guard case let .ready(bytes) = modelStatus.state(for: model) else {
            Log.app.error("Model size unavailable after download: \(model.rawValue)")
            return
        }
        analytics.capture(.modelDownload(model: model, seconds: Int(seconds), success: true, bytes: Int(bytes)))
    }

    private func observeWake() {
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.hotkeyMonitor?.recreate() }
            }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                MainActor.assumeIsolated { self?.hotkeyMonitor?.checkHealth() }
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.dictation.stopIfRecording() }
        }
    }
}
