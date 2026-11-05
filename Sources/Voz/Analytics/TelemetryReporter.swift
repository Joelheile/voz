import AppKit

/// Counts what happens on this Mac and turns finished days into facts. Nothing here touches the network directly.
@MainActor
final class TelemetryReporter {
    private static let reportInterval: Duration = .seconds(3600)

    private let settings: AppSettings
    private let analytics: Analytics
    private let store: TelemetryStore
    private let sender: TelemetrySender
    private let home: VozHome
    private let defaults: UserDefaults
    private let isActive: Bool
    private let environment: TelemetryEnvironment
    private let now: @MainActor () -> Date
    private let isPublicWindow: @MainActor (HostApp) async -> Bool

    init(
        settings: AppSettings,
        analytics: Analytics,
        store: TelemetryStore = .shared,
        sender: TelemetrySender = TelemetrySender(key: TelemetrySender.anonymousKey, spacingSeconds: TelemetrySender.anonymousSpacingSeconds),
        home: VozHome = VozHome(),
        defaults: UserDefaults = .standard,
        isActive: Bool = SystemContext.sendsTelemetry,
        environment: TelemetryEnvironment = .current,
        now: @escaping @MainActor () -> Date = { Date() },
        isPublicWindow: @escaping @MainActor (HostApp) async -> Bool = TelemetryReporter.isReadablePublicWindow
    ) {
        self.settings = settings
        self.analytics = analytics
        self.store = store
        self.sender = sender
        self.home = home
        self.defaults = defaults
        self.isActive = isActive
        self.environment = environment
        self.now = now
        self.isPublicWindow = isPublicWindow
    }

    /// Reports at launch and hourly, so someone's last day still arrives without another dictation
    func start(launch: LaunchVersion) {
        guard isActive else { return }
        let pingID = InstallID(key: InstallID.versionPing, defaults: defaults)
        if let ping = VersionPing(pingIDIsNew: pingID.isNew, updatedFrom: launch.updatedFrom) {
            let fact = TelemetryFact.versionPing(ping, version: launch.current, previous: launch.updatedFrom)
            send([DatedFact(fact: fact, day: TelemetryStore.day(of: now()))])
        }
        sender.drain()
        report()
        Task { [weak self] in
            while (try? await Task.sleep(for: Self.reportInterval)) != nil {
                self?.report()
            }
        }
    }

    func report() {
        guard isActive else { return }
        let ready = store.takeReady(now: now())
        let weekly = ready.weeklyDay.map { day in weeklyFacts().map { DatedFact(fact: $0, day: day) } } ?? []
        send(ready.facts + weekly)
    }

    func recordDictation(app: HostApp, model: String, words: Int, totalMs: Int) {
        guard isActive else { return }
        store.addDictation(app: .app(app.bundleID), model: .model(model), words: words, totalMs: totalMs, now: now())
        report()
        Task { [weak self] in await self?.recordSite(of: app, words: words) }
    }

    /// Sites count only with the opt-in, which can change while the window check runs
    func recordSite(of app: HostApp, words: Int) async {
        guard settings.analyticsEnabled, let website = app.website, await isPublicWindow(app), settings.analyticsEnabled else { return }
        store.addSite(.site(website), words: words, now: now())
    }

    func recordExtension(named name: String) {
        guard isActive else { return }
        do {
            store.addExtensionRun(TelemetryName.package(named: name, in: try home.installedExtensions()), now: now())
        } catch {
            Log.extensions.error("Could not read installed extensions: \(error.localizedDescription, privacy: .public)")
        }
    }

    func clearSites() {
        store.clearSites()
    }

    private func send(_ facts: [DatedFact]) {
        analytics.send(facts.filter(\.fact.isLinked))
        do {
            sender.send(try facts.filter { !$0.fact.isLinked }.map { try TelemetryPayload.body($0, installID: UUID(), environment: environment) })
        } catch {
            Log.app.error("Could not encode telemetry: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func weeklyFacts() -> [TelemetryFact] {
        let settingsFact = TelemetryFact.settingsWeek(SettingsSnapshot(
            cleanup: settings.cleanupEnabled, livePreview: settings.livePreviewEnabled, insertIntoApp: settings.insertIntoApp,
            soundCues: settings.soundCues, launchAtLogin: settings.launchAtLogin, autoUpdate: settings.installUpdatesAutomatically,
            betaUpdates: settings.receiveBetaUpdates, shareUsage: settings.analyticsEnabled, crashReports: settings.errorReportsEnabled,
            speechModel: .model(settings.speechModel)
        ))
        do {
            let disabled = try home.disabledExtensions()
            let installed = try home.installedExtensions()
            let packages = installed.filter { !disabled.contains($0.name) }.compactMap { TelemetryName.package(named: $0.name, in: installed) }
            return [settingsFact] + packages.map(TelemetryFact.extensionWeek)
        } catch {
            Log.extensions.error("Could not read installed extensions: \(error.localizedDescription, privacy: .public)")
            return [settingsFact]
        }
    }

    /// Unsure means private: a site only counts when the browser is in front and its window reads as a normal one
    private static func isReadablePublicWindow(_ app: HostApp) async -> Bool {
        guard let bundleID = app.bundleID, ScreenText.browsers.contains(bundleID),
              let front = NSWorkspace.shared.frontmostApplication, front.bundleIdentifier == bundleID else { return false }
        let pid = front.processIdentifier
        return await Task.detached {
            guard let window = FieldReader.windowLabels(pid: pid) else { return false }
            return !ScreenText.isPrivate(app: bundleID, window: window.title, toolbar: window.toolbar)
        }.value
    }
}
