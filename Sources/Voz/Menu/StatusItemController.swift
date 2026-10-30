import AppKit
import Combine
import SwiftUI

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

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let action = Self.editAction(for: event), firstResponder?.tryToPerform(action, with: self) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    private static func editAction(for event: NSEvent) -> Selector? {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock)
        return switch (modifiers, event.charactersIgnoringModifiers?.lowercased()) {
        case (.command, "x"): #selector(NSText.cut(_:))
        case (.command, "c"): #selector(NSText.copy(_:))
        case (.command, "v"): #selector(NSText.paste(_:))
        case (.command, "a"): #selector(NSText.selectAll(_:))
        case (.command, "z"): Selector(("undo:"))
        case ([.command, .shift], "z"): Selector(("redo:"))
        default: nil
        }
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
    private static let anchorRetry: TimeInterval = 0.1
    private static let shrinkDelay: TimeInterval = 0.35

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let model = PopoverModel()
    private let panel = PopoverPanel()
    private let hosting: PopoverHostingView
    private let dictation: Dictation
    private let settings: AppSettings
    private let modelStatus: ModelStatus
    private let stats: StatsModel
    private let history: HistoryModel
    private let catalog: ExtensionCatalog
    private let setup: SetupModel
    private let analytics: Analytics
    private let checkForUpdates: () -> Void
    private let quitApp: () -> Void
    private var cancellables: Set<AnyCancellable> = []
    private var outsideClickMonitor: Any?
    private var permissionPoll: Task<Void, Never>?
    private var permissions: PermissionSnapshot?
    private var closedAt = Date.distantPast
    private var contentSize: CGSize = .zero

    init(
        dictation: Dictation,
        sources: PopoverSources,
        analytics: Analytics,
        copy: @escaping (TranscriptRecord) -> Void,
        checkForUpdates: @escaping () -> Void,
        retryModel: @escaping () -> Void,
        finishSetup: @escaping () -> Void,
        quit: @escaping () -> Void
    ) {
        self.dictation = dictation
        settings = sources.settings
        modelStatus = sources.modelStatus
        history = sources.history
        catalog = sources.catalog
        stats = sources.stats
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
            copy: copy,
            fixPermission: { [weak self] in self?.fix($0) },
            retryModel: retryModel,
            checkForUpdates: { [weak self] in self?.dismissThen(checkForUpdates) },
            finishSetup: { [weak self] in
                self?.closePanel()
                finishSetup()
            },
            resize: { [weak self] in self?.resize(to: $0) },
            quit: quit
        )
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        observeSources()
        refresh()
        Task { await readPermissions() }
        DispatchQueue.main.async { [hosting] in hosting.layoutSubtreeIfNeeded() }
    }

    func refresh() {
        statusItem.button?.image = MenuBarGlyph.image(for: dictation.phase, busy: !catalog.activities.isEmpty)
        statusItem.button?.setAccessibilityLabel("Voz")
        let status = currentStatus()
        let hint = hint(for: status)
        let needsSetup = !settings.onboardingCompleted
        if model.status != status { model.status = status }
        if model.hint != hint { model.hint = hint }
        if model.needsSetup != needsSetup { model.needsSetup = needsSetup }
        if model.needsSetup, let permissions { setup.apply(permissions) }
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
        Publishers.Merge3(
            settings.objectWillChange.map { _ in () },
            modelStatus.objectWillChange.map { _ in () },
            catalog.$activities.map(\.isEmpty).removeDuplicates().map { _ in () }
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] in self?.refresh() }
        .store(in: &cancellables)
        model.$page
            .removeDuplicates()
            .sink { [weak self] page in
                self?.syncStats(page: page)
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
        switch permissions?.microphone {
        case .notDetermined: return .permissionNeeded(.microphone)
        case .denied, .restricted: return .permissionNeeded(.microphoneBlocked)
        default: break
        }
        if permissions?.accessibility == false { return .permissionNeeded(.accessibility) }
        switch modelStatus.state(for: settings.localSpeechModel) {
        case .ready: return .ready
        case .notLoaded: return .loadingModel(detail: "Starting", progress: nil)
        case let .downloading(fraction):
            let detail = DownloadEstimate.detail(fraction: fraction, elapsed: modelStatus.downloadElapsed(for: settings.localSpeechModel))
            return .loadingModel(detail: detail, progress: fraction)
        case .compiling: return .loadingModel(detail: "Optimizing for this Mac, about 20 seconds", progress: nil)
        case let .failed(message): return .modelFailed(message)
        }
    }

    private func hint(for status: PopoverStatus) -> String {
        switch status {
        case .ready where iconIsBehindNotch: "\(DictationHint.idle(hotkey: settings.hotkey, holdToTalk: settings.holdToTalk)). \(MenuBarNotch.hint)"
        case .ready: DictationHint.idle(hotkey: settings.hotkey, holdToTalk: settings.holdToTalk)
        case .recording: history.records.isEmpty ? DictationHint.recording(hotkey: settings.hotkey, holdToTalk: settings.holdToTalk) : ""
        case .transcribing: "Turning your speech into text"
        case let .loadingModel(detail, _): detail
        case let .modelFailed(message): message
        case let .permissionNeeded(fix): fix.detail
        }
    }

    private var iconIsBehindNotch: Bool {
        guard let window = statusItem.button?.window, let screen = window.screen else { return false }
        return MenuBarNotch.hides(window.frame, on: screen)
    }

    private func fix(_ fix: PermissionFix) {
        switch fix {
        case .microphone: Task { await Permissions.requestMicrophone() }
        case .microphoneBlocked: Permissions.openSettings(.microphone)
        case .accessibility: Permissions.requestAccessibility()
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
        layoutPanel(size: contentSize)
        panel.makeKeyAndOrderFront(nil)
        syncStats(page: model.page)
        statusItem.button?.highlight(true)
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismissUnlessPinned() }
        }
        permissionPoll = Task { [weak self] in
            while !Task.isCancelled {
                await self?.readPermissions()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func readPermissions() async {
        let latest = await PermissionSnapshot.read()
        guard latest != permissions else { return }
        permissions = latest
        refresh()
    }

    private func syncStats(page: PopoverPage) {
        guard panel.isVisible, !model.needsSetup, page == .insights else { return stats.stop() }
        stats.start()
    }

    private func closePanel() {
        guard panel.isVisible else { return }
        stats.stop()
        panel.orderOut(nil)
        closedAt = Date()
        statusItem.button?.highlight(false)
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
        permissionPoll?.cancel()
        permissionPoll = nil
        history.query = ""
    }

    private func dismissThen(_ action: () -> Void) {
        closePanel()
        action()
    }

    private func resize(to size: CGSize) {
        contentSize = size
        guard panel.isVisible else { return }
        guard size.height < panel.frame.height else { return layoutPanel(size: size) }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.shrinkDelay) { [weak self] in
            guard let self, self.panel.isVisible, self.contentSize == size else { return }
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

enum MenuBarGlyph {
    private static let height: CGFloat = 16
    private static let transcribingOpacity: CGFloat = 0.45

    private static let icon: NSImage = {
        guard let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            fatalError("MenuBarIcon.png missing from app bundle")
        }
        image.size = NSSize(width: (height * image.size.width / image.size.height).rounded(), height: height)
        image.isTemplate = true
        return image
    }()

    private static let dimmedIcon: NSImage = {
        let image = NSImage(size: icon.size, flipped: false) { rect in
            icon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: transcribingOpacity)
            return true
        }
        image.isTemplate = true
        return image
    }()

    private static let badgeSize: CGFloat = 5

    private static let busyIcon: NSImage = {
        let image = NSImage(size: icon.size, flipped: false) { rect in
            icon.draw(in: rect)
            let badge = NSRect(x: rect.maxX - badgeSize, y: rect.maxY - badgeSize, width: badgeSize, height: badgeSize)
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: badge.insetBy(dx: -1.5, dy: -1.5)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.black.setFill()
            NSBezierPath(ovalIn: badge).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()

    static func image(for phase: DictationPhase, busy: Bool) -> NSImage {
        if phase == .transcribing { return dimmedIcon }
        return busy ? busyIcon : icon
    }
}
