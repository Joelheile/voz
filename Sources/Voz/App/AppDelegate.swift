import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let modelStatus = ModelStatus()
    private let installID = InstallID(key: InstallID.usage)
    private lazy var analytics = Analytics(usage: settings.analyticsEnabled, errors: settings.errorReportsEnabled, installID: installID.value)
    private let history = AppDelegate.openHistory()
    private lazy var transcriber = Transcriber { [modelStatus] mode, state in
        DispatchQueue.main.async { MainActor.assumeIsolated { modelStatus.update(mode, state) } }
    }
    private lazy var speechEngine = SpeechEngine(parakeet: transcriber)
    private lazy var output = TextOutput(settings: settings)
    private let cleaner = TextCleaner()
    private let toast = ToastController()
    private let headphoneQuality = HeadphoneQuality()
    private lazy var extensions = ExtensionService(
        output: output,
        toast: toast,
        settings: settings,
        fileTranscriber: FileTranscriber(transcriber: transcriber, vocabulary: history.vocabulary),
        drafts: history.drafts
    )
    private var vocabularyWords: [String] = []
    private lazy var vocabularyLearner = VocabularyLearner(
        store: history.vocabulary,
        hear: { [transcriber, settings] in await SpokenWord.hear($0, transcriber: transcriber, settings: settings) }
    )
    private lazy var telemetry = TelemetryReporter(settings: settings, analytics: analytics)
    private lazy var dictation = Dictation(
        pipeline: DictationPipeline(
            engine: speechEngine,
            cleaner: cleaner,
            settings: settings,
            history: history,
            output: output,
            editObserver: EditObserver(learner: vocabularyLearner),
            vocabularyLearner: vocabularyLearner,
            analytics: analytics,
            extensions: extensions,
            telemetry: telemetry
        ),
        settings: settings,
        analytics: analytics
    )
    private var cancellables: Set<AnyCancellable> = []
    private lazy var historyModel = HistoryModel(store: history)
    private lazy var statsModel = StatsModel(store: history)
    private lazy var vocabularyModel = VocabularyModel(store: history.vocabulary, analytics: analytics)
    private lazy var setupModel = SetupModel(analytics: analytics) { [weak self] in self?.retryModel() }
    private lazy var extensionsModel = ExtensionsModel(analytics: analytics)
    private var statusItemController: StatusItemController?
    private var hotkeyMonitor: HotkeyMonitor?
    private let indicator = IndicatorController()
    private lazy var dropSensor = DropSensor(
        onInvite: { [weak self] screen in self?.inviteDrop(on: screen) },
        onEnter: { [weak self] screen in self?.offerDrop(on: screen) ?? false },
        onDrop: { [weak self] file in self?.transcribeDropped(file) }
    )
    private let uninstallWatcher = UninstallWatcher()
    private var controlServer: ControlServer?
    private let notices = NoticeController()
    private lazy var updater = Updater(
        settings: settings,
        isBusy: { [weak self] in
            guard let self else { return true }
            return RestartGuard.blocksRestart(
                dictating: self.dictation.phase != .idle,
                runningActivities: self.extensions.catalog.activities.count,
                asking: self.extensions.isAsking
            )
        },
        showNotice: { [notices] notice in
            await notices.show(title: notice.title, icon: .circleArrowUp, later: UpdateNotice.later, action: notice.action) == notice.action
        }
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !LoginItem.isInTrash else {
            LoginItem.unregister()
            return NSApp.terminate(nil)
        }
        let launchedAtLogin = LoginItem.launchedAtLogin
        uninstallWatcher.start()
        extensions.start()
        startControlServer()
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
                catalog: extensions.catalog,
                updater: updater
            ),
            analytics: analytics,
            copy: { [output] in output.copy($0) },
            checkForUpdates: { [weak self] in self?.updater.checkForUpdates() },
            retryModel: { [weak self] in self?.retryModel() },
            finishSetup: { [weak self] in self?.finishSetup() },
            toast: { [toast] in toast.show($0) },
            quit: { NSApp.terminate(nil) }
        )
        self.statusItemController = statusItemController
        dictation.onChange = { [weak self] in
            guard let self else { return }
            self.statusItemController?.dictationChanged()
            self.indicator.sync(phase: self.dictation.phase)
            self.updater.resumePendingInstall()
        }
        dictation.onStartFailed = { [toast] in toast.show($0) }
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
        let showOutcome = dictation.onOutcome
        dictation.onOutcome = { [weak self] outcome in
            showOutcome(outcome)
            if case .done = outcome { self?.suggestStarIfDue() }
        }
        indicator.onCancelWork = { [weak self] in self?.extensions.cancelWork() }
        indicator.live = extensions.liveStatus
        indicator.onOpenActivity = { [catalog = extensions.catalog] in catalog.open($0) }
        indicator.onStopActivity = { [catalog = extensions.catalog] in catalog.stop($0) }
        extensions.catalog.$activities
            .map { $0.first(where: \.openable) ?? $0.first }
            .removeDuplicates()
            .sink { [indicator] in indicator.show($0) }
            .store(in: &cancellables)
        extensions.onFileProgress = { [weak self] fraction in self?.indicator.showFileProgress(fraction) }
        extensions.onExtensionUsed = { [weak self] name in self?.telemetry.recordExtension(named: name) }
        extensions.onWorking = { [weak self] in
            guard let self, self.dictation.phase == .idle else { return }
            self.indicator.showWorking()
        }
        extensions.onWorked = { [weak self] succeeded in self?.indicator.finishWork(succeeded: succeeded) }
        extensions.onHistory = { [history] entry in
            do {
                try history.insert(TranscriptRecord(entry))
            } catch {
                Log.extensions.error("History write failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        dropSensor.start()
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
            if !SystemContext.isTestBuild {
                Task { await Permissions.repairStaleGrants() }
            }
        } else if !SystemContext.isTestBuild {
            statusItemController.open()
        }
        hotkeyMonitor?.checkHealth()
        let launch = LaunchVersion.record(SystemContext.appVersion, in: .standard)
        if let previous = launch.updatedFrom {
            analytics.capture(.updateInstalled(from: previous, to: launch.current, channel: UpdateChannel(version: launch.current)))
        }
        telemetry.start(launch: launch)
        updater.start()
        LoginItem.sync(enabled: settings.launchAtLogin)
        if !launchedAtLogin, launch.updatedFrom == nil, !SystemContext.isTestBuild { statusItemController.open() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let name = urls.lazy.compactMap(ExtensionLink.packageName(in:)).first else { return }
        statusItemController?.open(.extensions)
        Task { await extensionsModel.reveal(name) }
    }

    private var acceptsAudioDrop: Bool {
        extensions.acceptsAudioDrops && dictation.phase == .idle
    }

    private func inviteDrop(on screen: NSScreen) {
        guard acceptsAudioDrop else { return }
        indicator.inviteDrop(on: screen)
    }

    private func offerDrop(on screen: NSScreen) -> Bool {
        guard acceptsAudioDrop else {
            Log.app.notice("Drop refused: extension listens \(self.extensions.acceptsAudioDrops), dictation idle \(self.dictation.phase == .idle)")
            return false
        }
        return indicator.showDropTarget(on: screen)
    }

    private func transcribeDropped(_ file: URL) {
        indicator.showWorking()
        Task {
            let succeeded = await extensions.dropAudio(file)
            if !succeeded { Log.app.error("Dropped .\(file.pathExtension, privacy: .public) file failed in the extension") }
            indicator.finishWork(succeeded: succeeded)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusItemController?.open()
        return false
    }

    private func startControlServer() {
        let commands = ControlCommands(
            history: history, settings: settings, extensions: extensionsModel, catalog: extensions.catalog,
            dictation: .init(
                phase: { [dictation] in dictation.phase },
                handle: { [dictation] in dictation.handle($0) },
                stopWithoutInserting: { [dictation] in dictation.stopWithoutInserting() }
            ),
            modelStatus: modelStatus
        )
        let server = ControlServer(center: ControlCenter(commands: commands.all))
        do {
            try server.start()
            controlServer = server
        } catch {
            Log.app.error("Could not start the control socket: \(String(describing: error), privacy: .public)")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controlServer?.stop()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard analytics.reportsCrashes else { return .terminateNow }
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
        settings.$headphoneQuality
            .sink { [headphoneQuality] in headphoneQuality.isOn = $0 }
            .store(in: &cancellables)
        settings.$launchAtLogin
            .dropFirst()
            .sink { LoginItem.sync(enabled: $0) }
            .store(in: &cancellables)
        settings.$receiveBetaUpdates
            .dropFirst()
            .filter { $0 }
            .sink { [weak self] _ in self?.updater.checkForUpdatesInBackground() }
            .store(in: &cancellables)
        settings.$analyticsEnabled.combineLatest(settings.$errorReportsEnabled)
            .dropFirst()
            .sink { [weak self] usage, errors in
                self?.analytics.setConsent(usage: usage, errors: errors)
                if !usage { self?.telemetry.clearSites() }
            }
            .store(in: &cancellables)
        settings.$microphone
            .dropFirst()
            .receive(on: DispatchQueue.main) // @Published emits before the new value is stored
            .sink { [weak self] _ in self?.dictation.prepareRecorder() }
            .store(in: &cancellables)
        settings.$speechModel
            .map { SpeechModel(rawValue: $0) ?? .parakeetUltra }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] model in self?.warmUpModel(model) }
            .store(in: &cancellables)
        settings.$languages
            .removeDuplicates()
            .sink { [transcriber] languages in Task { await transcriber.setLanguages(languages) } }
            .store(in: &cancellables)
        Publishers.CombineLatest3(settings.$cleanupPrompt, settings.$cleanupMode, settings.$languages)
            .dropFirst()
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.prewarmCleanup() }
            .store(in: &cancellables)
    }

    private func prewarmCleanup() {
        let plan = CleanupPlan(prompt: settings.cleanupPrompt, mode: settings.cleanupMode)
        cleaner.prewarm(CleanupSetup(plan: plan, vocabulary: vocabularyWords, languages: settings.languages))
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
        let terms: [VocabularyTerm]
        do {
            terms = try history.vocabulary.terms()
        } catch {
            Log.app.error("Vocabulary read failed: \(error.localizedDescription, privacy: .private)")
            return
        }
        let words = terms.map(\.word)
        vocabularyWords = words
        prewarmCleanup()
        Task {
            do {
                try await transcriber.prepareVocabulary(terms)
            } catch {
                Log.app.error("Vocabulary boosting setup failed: \(error.localizedDescription, privacy: .private)")
            }
        }
    }

    private func finishSetup() {
        setupModel.reportCompletion()
        settings.onboardingCompleted = true
    }

    private func suggestStarIfDue() {
        guard !settings.starToastShown, !settings.starPromptDismissed else { return }
        Task {
            guard let usage = await historyModel.usage(), StarPrompt.isDue(in: usage, dismissals: settings.starPromptDismissals) else { return }
            settings.starToastShown = true
            toast.show("Enjoying Voz? Give it a star on GitHub from the menu bar.")
        }
    }

    private func retryModel() {
        warmUpModel(settings.localSpeechModel)
    }

    private func warmUpModel(_ model: SpeechModel) {
        let wasDownloaded = model.isDownloaded
        Task {
            let started = Date()
            do {
                try await speechEngine.prepare(model)
                await transcriber.removeUnusedModels(keeping: model)
                let seconds = Date().timeIntervalSince(started)
                Log.app.notice("Model \(model.rawValue) ready in \(seconds, format: .fixed(precision: 1))s")
                reportModelReady(model, wasDownloaded: wasDownloaded, seconds: seconds)
            } catch TranscriberError.superseded {
                Log.app.notice("Model \(model.rawValue) load stopped for a newer choice")
            } catch {
                Log.app.error("Model load failed: \(error.localizedDescription, privacy: .private)")
                if !wasDownloaded {
                    analytics.capture(.modelDownload(model: model, seconds: Int(Date().timeIntervalSince(started)), success: false, bytes: 0))
                } else {
                    analytics.capture(.modelFailed(model: model))
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
