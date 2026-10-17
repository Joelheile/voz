import AppKit
import Combine
import SwiftUI
import VozCore

final class PopoverPanel: NSPanel {
    var onDismiss: () -> Void = {}

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onDismiss()
    }

    override func resignKey() {
        super.resignKey()
        onDismiss()
    }
}

@MainActor
final class StatusItemController: NSObject {
    private static let panelGap: CGFloat = 6
    private static let screenMargin: CGFloat = 8
    private static let reopenGuard: TimeInterval = 0.2
    private static let fade: TimeInterval = 0.12

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let model = PopoverModel()
    private let panel = PopoverPanel()
    private let hosting: NSHostingView<PopoverView>
    private let dictation: Dictation
    private let settings: AppSettings
    private let modelStatus: ModelStatus
    private let history: HistoryStore
    private let stats: StatsModel
    private let openApp: () -> Void
    private let openSettings: () -> Void
    private let checkForUpdates: () -> Void
    private var cancellables: Set<AnyCancellable> = []
    private var outsideClickMonitor: Any?
    private var permissionPoll: Timer?
    private var closedAt = Date.distantPast

    init(
        dictation: Dictation,
        settings: AppSettings,
        modelStatus: ModelStatus,
        history: HistoryStore,
        stats: StatsModel,
        openApp: @escaping () -> Void,
        openSettings: @escaping () -> Void,
        checkForUpdates: @escaping () -> Void
    ) {
        self.dictation = dictation
        self.settings = settings
        self.modelStatus = modelStatus
        self.history = history
        self.stats = stats
        self.openApp = openApp
        self.openSettings = openSettings
        self.checkForUpdates = checkForUpdates
        hosting = NSHostingView(rootView: PopoverView(model: model))
        super.init()
        hosting.sizingOptions = [.intrinsicContentSize]
        panel.contentView = hosting
        panel.onDismiss = { [weak self] in self?.closePanel() }
        model.actions = PopoverActions(
            copy: { [dictation] in dictation.copy($0.finalText) },
            retry: { [weak self] in
                self?.closePanel()
                self?.dictation.retryLast()
            },
            openApp: { [weak self] in self?.dismissThen(openApp) },
            openSettings: { [weak self] in self?.dismissThen(openSettings) },
            fixPermission: { [weak self] in self?.fix($0) },
            quit: { NSApp.terminate(nil) }
        )
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        observeSources()
        refresh()
    }

    func refresh() {
        statusItem.button?.image = MenuBarGlyph.image(for: dictation.phase)
        statusItem.button?.setAccessibilityLabel("voz")
        let status = currentStatus()
        model.status = status
        model.hint = hint(for: status)
        model.wordsThisWeek = stats.stats.wordsThisWeek
        model.canRetry = dictation.hasLastRecording && dictation.phase == .idle
    }

    func reloadTranscripts() {
        do {
            model.transcripts = try history.recent(limit: 3)
        } catch {
            Log.app.error("History read failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    func dictationChanged() {
        refresh()
        if dictation.phase == .idle { reloadTranscripts() }
    }

    private func observeSources() {
        Publishers.Merge3(
            settings.objectWillChange.map { _ in () },
            modelStatus.objectWillChange.map { _ in () },
            stats.$stats.map { _ in () }
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] in self?.refresh() }
        .store(in: &cancellables)
        model.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self, self.panel.isVisible else { return }
                self.layoutPanel()
            }
            .store(in: &cancellables)
    }

    private func currentStatus() -> PopoverStatus {
        switch dictation.phase {
        case .recording: return .recording
        case .transcribing: return .transcribing
        case .idle: break
        }
        switch Permissions.microphoneStatus {
        case .notDetermined: return .permissionNeeded(.microphone)
        case .denied, .restricted: return .permissionNeeded(.microphoneBlocked)
        default: break
        }
        if !Permissions.accessibilityGranted { return .permissionNeeded(.accessibility) }
        switch modelStatus.state(for: settings.languageMode) {
        case .ready: return .ready
        case .notLoaded: return .loadingModel(detail: "Starting up", progress: nil)
        case let .downloading(fraction):
            let percent = fraction.formatted(.percent.precision(.fractionLength(0)))
            return .loadingModel(detail: "Downloading the speech model, \(percent)", progress: fraction)
        case .compiling: return .loadingModel(detail: "Preparing the speech model for first use", progress: nil)
        case let .failed(message): return .modelFailed(message)
        }
    }

    private func hint(for status: PopoverStatus) -> String {
        switch status {
        case .ready: DictationHint.idle(hotkey: settings.hotkey, holdToTalk: settings.holdToTalk)
        case .recording: DictationHint.recording(hotkey: settings.hotkey, holdToTalk: settings.holdToTalk)
        case .transcribing: "Cleaning up your text"
        case let .loadingModel(detail, _): detail
        case let .modelFailed(message): message
        case let .permissionNeeded(fix): fix.detail
        }
    }

    private func fix(_ fix: PermissionFix) {
        switch fix {
        case .microphone: Task { await Permissions.requestMicrophone() }
        case .microphoneBlocked: Permissions.openSettings(pane: "Privacy_Microphone")
        case .accessibility: Permissions.promptForAccessibility()
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            closePanel()
            showFallbackMenu()
        } else if panel.isVisible {
            closePanel()
        } else if Date().timeIntervalSince(closedAt) > Self.reopenGuard {
            showPanel()
        }
    }

    private func showPanel() {
        refresh()
        reloadTranscripts()
        layoutPanel()
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fade
            panel.animator().alphaValue = 1
        }
        statusItem.button?.highlight(true)
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.closePanel() }
        }
        permissionPoll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    private func closePanel() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        closedAt = Date()
        statusItem.button?.highlight(false)
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
        permissionPoll?.invalidate()
        permissionPoll = nil
    }

    private func dismissThen(_ action: () -> Void) {
        closePanel()
        action()
    }

    private func layoutPanel() {
        guard let buttonWindow = statusItem.button?.window, let button = statusItem.button else { return }
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame ?? anchor
        let x = min(max(anchor.midX - size.width / 2, visible.minX + Self.screenMargin), visible.maxX - size.width - Self.screenMargin)
        panel.setFrame(NSRect(x: x, y: anchor.minY - Self.panelGap - size.height, width: size.width, height: size.height), display: true)
        panel.invalidateShadow()
    }

    private func showFallbackMenu() {
        let menu = NSMenu()
        menu.addItem(menuItem("Open voz", #selector(openAppClicked)))
        menu.addItem(menuItem("Settings…", #selector(openSettingsClicked), key: ","))
        menu.addItem(menuItem("Check for Updates…", #selector(checkForUpdatesClicked)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit voz", #selector(quit), key: "q"))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func menuItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func openAppClicked() { openApp() }
    @objc private func openSettingsClicked() { openSettings() }
    @objc private func checkForUpdatesClicked() { checkForUpdates() }
    @objc private func quit() { NSApp.terminate(nil) }
}
