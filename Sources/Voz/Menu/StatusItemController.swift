import AppKit
import Combine
import SwiftUI
import VozCore

final class PopoverPanel: NSPanel {
    var onCancel: () -> Void = {}
    var onResignKey: () -> Void = {}

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
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
        onCancel()
    }

    override func resignKey() {
        super.resignKey()
        onResignKey()
    }
}

final class PopoverHostingView: NSHostingView<PopoverView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class StatusItemController: NSObject {
    private static let panelGap: CGFloat = 6
    private static let screenMargin: CGFloat = 8
    private static let reopenGuard: TimeInterval = 0.2
    private static let fade: TimeInterval = 0.12
    private static let anchorRetry: TimeInterval = 0.1
    private static let shrinkDelay: TimeInterval = 0.35

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let model = PopoverModel()
    private let panel = PopoverPanel()
    private let hosting: PopoverHostingView
    private let dictation: Dictation
    private let settings: AppSettings
    private let modelStatus: ModelStatus
    private let history: HistoryModel
    private let setup: SetupModel
    private let analytics: Analytics
    private let checkForUpdates: () -> Void
    private let quitApp: () -> Void
    private var cancellables: Set<AnyCancellable> = []
    private var outsideClickMonitor: Any?
    private var permissionPoll: Timer?
    private var closedAt = Date.distantPast
    private var pendingSize: CGSize?

    init(
        dictation: Dictation,
        sources: PopoverSources,
        analytics: Analytics,
        checkForUpdates: @escaping () -> Void,
        retryModel: @escaping () -> Void,
        finishSetup: @escaping () -> Void,
        quit: @escaping () -> Void
    ) {
        self.dictation = dictation
        settings = sources.settings
        modelStatus = sources.modelStatus
        history = sources.history
        setup = sources.setup
        self.analytics = analytics
        self.checkForUpdates = checkForUpdates
        quitApp = quit
        hosting = PopoverHostingView(rootView: PopoverView(model: model, sources: sources))
        super.init()
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.onCancel = { [weak self] in self?.cancel() }
        panel.onResignKey = { [weak self] in self?.dismissUnlessPinned() }
        model.actions = PopoverActions(
            copy: { [dictation] in dictation.copy($0.finalText) },
            fixPermission: { [weak self] in self?.fix($0) },
            retryModel: retryModel,
            checkForUpdates: { [weak self] in self?.dismissThen(checkForUpdates) },
            finishSetup: { [weak self] in
                self?.closePanel()
                finishSetup()
            },
            resize: { [weak self] size in
                guard let self, self.panel.isVisible else { return }
                self.resize(to: size)
            },
            quit: quit
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
        statusItem.button?.setAccessibilityLabel("Voz")
        let status = currentStatus()
        model.status = status
        model.hint = hint(for: status)
        model.needsSetup = !settings.onboardingCompleted
        if model.needsSetup { setup.refreshPermissions() }
    }

    func dictationChanged() {
        refresh()
    }

    func open(_ page: PopoverPage = .home) {
        model.page = page
        guard !panel.isVisible else { return }
        showPanel()
    }

    private func observeSources() {
        Publishers.Merge(
            settings.objectWillChange.map { _ in () },
            modelStatus.objectWillChange.map { _ in () }
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] in self?.refresh() }
        .store(in: &cancellables)
        model.$page
            .removeDuplicates()
            .sink { [weak self] page in
                if page == .insights { self?.analytics.capture(.statsOpened) }
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
        switch modelStatus.state(for: settings.localSpeechModel) {
        case .ready: return .ready
        case .notLoaded: return .loadingModel(detail: "Starting", progress: nil)
        case let .downloading(fraction):
            let percent = fraction.formatted(.percent.precision(.fractionLength(0)))
            return .loadingModel(detail: "Downloading speech model, \(percent)", progress: fraction)
        case .compiling: return .loadingModel(detail: "Preparing the speech model", progress: nil)
        case let .failed(message): return .modelFailed(message)
        }
    }

    private func hint(for status: PopoverStatus) -> String {
        switch status {
        case .ready: DictationHint.idle(hotkey: settings.hotkey, holdToTalk: settings.holdToTalk)
        case .recording: DictationHint.recording(hotkey: settings.hotkey, holdToTalk: settings.holdToTalk)
        case .transcribing: "Turning your speech into text"
        case let .loadingModel(detail, _): detail
        case let .modelFailed(message): message
        case let .permissionNeeded(fix): fix.detail
        }
    }

    private func fix(_ fix: PermissionFix) {
        switch fix {
        case .microphone: Task { await Permissions.requestMicrophone() }
        case .microphoneBlocked: Permissions.openSettings(.microphone)
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
            open()
        }
    }

    private func cancel() {
        guard model.needsSetup || model.page == .home else { return model.goBack() }
        closePanel()
    }

    private func dismissUnlessPinned() {
        guard !model.needsSetup else { return }
        closePanel()
    }

    private func showPanel() {
        analytics.capture(.appOpened)
        refresh()
        if !model.needsSetup { analytics.capture(.historyOpened) }
        hosting.layoutSubtreeIfNeeded()
        layoutPanel(size: hosting.fittingSize)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fade
            panel.animator().alphaValue = 1
        }
        statusItem.button?.highlight(true)
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismissUnlessPinned() }
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
        history.query = ""
    }

    private func dismissThen(_ action: () -> Void) {
        closePanel()
        action()
    }

    private func resize(to size: CGSize) {
        pendingSize = size
        guard size.height < panel.frame.height else { return layoutPanel(size: size) }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.shrinkDelay) { [weak self] in
            guard let self, self.panel.isVisible, self.pendingSize == size else { return }
            self.layoutPanel(size: size)
        }
    }

    private func layoutPanel(size: CGSize) {
        guard let buttonWindow = statusItem.button?.window, let button = statusItem.button else { return }
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let anchorIsOnScreen = NSScreen.screens.contains { $0.frame.contains(anchor) }
        guard anchorIsOnScreen else {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.anchorRetry) { [weak self] in
                guard let self, self.panel.isVisible else { return }
                self.layoutPanel(size: size)
            }
            return
        }
        let visible = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame ?? anchor
        let inset = PopoverView.shadowInset
        let x = min(max(anchor.midX - size.width / 2, visible.minX + Self.screenMargin - inset), visible.maxX - size.width - Self.screenMargin + inset)
        panel.setFrame(NSRect(x: x, y: anchor.minY - Self.panelGap + inset - size.height, width: size.width, height: size.height), display: true)
    }

    private func showFallbackMenu() {
        let menu = NSMenu()
        menu.addItem(menuItem("Settings…", #selector(openSettingsClicked), key: ","))
        menu.addItem(menuItem("Check for Updates…", #selector(checkForUpdatesClicked)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit Voz", #selector(quit), key: "q"))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func menuItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func openSettingsClicked() { open(.settings) }
    @objc private func checkForUpdatesClicked() { checkForUpdates() }
    @objc private func quit() { quitApp() }
}
