import AppKit
import Combine
import VozCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let modelStatus = ModelStatus()
    private let installID = InstallID()
    private lazy var analytics = Analytics(enabled: settings.analyticsEnabled, installID: installID.value)
    private var settingChangeReporter: SettingChangeReporter?
    private let history = AppDelegate.openHistory()
    private lazy var transcriber = Transcriber { [modelStatus] mode, state in
        DispatchQueue.main.async { MainActor.assumeIsolated { modelStatus.update(mode, state) } }
    }
    private lazy var output = TextOutput(settings: settings)
    private let cleaner = TextCleaner()
    private lazy var extensions = ExtensionService(output: output)
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
    private let mainModel = MainWindowModel()
    private lazy var historyModel = HistoryModel(store: history, copy: { [output] in output.copy($0) })
    private lazy var statsModel = StatsModel(store: history)
    private lazy var vocabularyModel = VocabularyModel(store: history.vocabulary, analytics: analytics)
    private lazy var mainWindow = HostedWindow(
        title: "voz",
        size: MainView.windowSize,
        minSize: MainView.minimumSize,
        content: MainView(
            model: mainModel,
            settings: settings,
            status: modelStatus,
            history: historyModel,
            stats: statsModel,
            vocabulary: vocabularyModel,
            checkForUpdates: { [weak self] in self?.updater.checkForUpdates() }
        )
    )
    private lazy var onboardingWindow = HostedWindow(
        title: "Welcome to voz",
        size: OnboardingView.windowSize,
        content: OnboardingView(
            model: OnboardingModel(
                analytics: analytics,
                onLanguageChosen: { [weak self] in self.map { $0.warmUpModel($0.settings.languageMode) } },
                onFinish: { [weak self] in self?.finishOnboarding() }
            ),
            settings: settings,
            modelStatus: modelStatus
        )
    )
    private var statusItemController: StatusItemController?
    private var hotkeyMonitor: HotkeyMonitor?
    private var permissionPoll: Timer?
    private let indicator = IndicatorController()
    private lazy var updater = Updater(settings: settings)

    func applicationDidFinishLaunching(_ notification: Notification) {
        dictation.recoverFromPreviousRun()
        extensions.start()
        let statusItemController = StatusItemController(
            dictation: dictation,
            settings: settings,
            modelStatus: modelStatus,
            history: history,
            stats: statsModel,
            openApp: { [weak self] in self?.showMain(.home) },
            openSettings: { [weak self] in self?.showMain(.settings) },
            checkForUpdates: { [weak self] in self?.updater.checkForUpdates() }
        )
        self.statusItemController = statusItemController
        dictation.onChange = { [weak statusItemController] in statusItemController?.dictationChanged() }
        observeSections()
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
        observeSettings()
        observeVocabulary()
        if settings.onboardingCompleted {
            Task { await Permissions.requestMicrophone() }
            warmUpModel(settings.languageMode)
            if !Permissions.accessibilityGranted {
                Permissions.promptForAccessibility()
            }
        } else {
            onboardingWindow.show()
        }
        startHotkeyWhenPermitted()
        settingChangeReporter = SettingChangeReporter(settings: settings, analytics: analytics)
        let launchMs = LaunchTimer.millisecondsSinceProcessStart()
        if let updateEvent = InstalledUpdateReporter(defaults: .standard).event(currentVersion: SystemContext.properties["app_version"] ?? "unknown") {
            analytics.capture(updateEvent)
        }
        updater.start()
        analytics.capture(installID.isNew ? .appInstalled(launchMs: launchMs) : .appLaunched(launchMs: launchMs))
        manageLaunchAgent()
    }

    private func manageLaunchAgent() {
        guard settings.launchAtLogin else { return LaunchAgent.unregisterIfRegistered() }
        Task {
            guard await LaunchAgent.handOver() else { return }
            NSApp.perform(#selector(NSApplication.terminate(_:)), with: nil, afterDelay: 0)
        }
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
        settings.$languageMode
            .dropFirst()
            .sink { [weak self] mode in
                guard let self, self.settings.onboardingCompleted else { return }
                self.warmUpModel(mode)
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
        cleaner.prewarm(vocabulary: words)
        Task {
            do {
                try await transcriber.prepareVocabulary(words)
            } catch {
                Log.app.error("Vocabulary boosting setup failed: \(error.localizedDescription, privacy: .private)")
            }
        }
    }

    private func showMain(_ section: MainSection) {
        mainModel.section = section
        mainWindow.show()
    }

    private func observeSections() {
        mainModel.$section
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] section in
                switch section {
                case .home: self?.analytics.capture(.historyOpened)
                case .insights: self?.analytics.capture(.statsOpened)
                case .dictionary, .settings: break
                }
            }
            .store(in: &cancellables)
    }

    private func finishOnboarding() {
        settings.onboardingCompleted = true
        onboardingWindow.close()
    }

    private func warmUpModel(_ mode: LanguageMode) {
        guard let model = SpeechModel(rawValue: mode.modelName) else {
            Log.app.error("Unknown speech model: \(mode.modelName)")
            return
        }
        let wasDownloaded = mode.isDownloaded
        Task {
            let started = Date()
            do {
                try await transcriber.prepare(mode)
                await transcriber.removeUnusedModels(keeping: mode)
                let seconds = Date().timeIntervalSince(started)
                Log.app.notice("Model \(mode.modelName) ready in \(seconds, format: .fixed(precision: 1))s")
                reportModelReady(model, wasDownloaded: wasDownloaded, seconds: seconds, mode: mode)
            } catch {
                Log.app.error("Model load failed: \(error.localizedDescription, privacy: .private)")
                if !wasDownloaded {
                    analytics.capture(.modelDownload(model: model, seconds: Int(Date().timeIntervalSince(started)), success: false, bytes: 0))
                }
            }
        }
    }

    private func reportModelReady(_ model: SpeechModel, wasDownloaded: Bool, seconds: Double, mode: LanguageMode) {
        guard !wasDownloaded else {
            return analytics.capture(.modelLoad(model: model, coldMs: Int(seconds * 1000)))
        }
        guard case let .ready(bytes) = modelStatus.state(for: mode) else {
            Log.app.error("Model size unavailable after download: \(model.rawValue)")
            return
        }
        analytics.capture(.modelDownload(model: model, seconds: Int(seconds), success: true, bytes: Int(bytes)))
    }

    private func startHotkeyWhenPermitted() {
        if tryStartHotkey() { return }
        permissionPoll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.tryStartHotkey() else { return }
                self.permissionPoll?.invalidate()
                self.permissionPoll = nil
            }
        }
    }

    private func tryStartHotkey() -> Bool {
        guard Permissions.accessibilityGranted, let hotkeyMonitor else { return false }
        let started = hotkeyMonitor.start()
        if started {
            Log.app.notice("Hotkey tap started")
            hotkeyMonitor.startHealthChecks()
        }
        return started
    }

    private func observeWake() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.hotkeyMonitor?.recreate() }
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
