import AppKit
import SwiftUI

@MainActor
final class IndicatorController {
    private static let doneHold = Duration.milliseconds(600)
    private static let discardHold = Duration.milliseconds(250)
    private static let failureHold = Duration.milliseconds(700)
    private static let closeDuration = Duration.milliseconds(300)
    private static let sampleInterval = 1.0 / 120

    private let model = IndicatorModel()
    private let panel = IndicatorPanel()
    private var layout: IndicatorLayout?
    private var lifecycle: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var lastPhase = Dictation.Phase.idle
    private var sampler: Timer?
    private var smoother = LevelSmoother()
    private var lastSampleTime = 0.0
    var levelSource: () -> Float = { 0 }

    init() {
        let reposition: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.repositionIfVisible() }
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main, using: reposition))
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: reposition))
    }

    func showRecording() {
        lifecycle?.cancel()
        clearPreview()
        if !panel.isVisible { present() }
        model.levels.reset()
        startSampling()
        model.recordingStart = .now
        model.recordingEnd = nil
        model.state = .recording
        lifecycle = Task { [model] in
            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled else { return }
            model.isExpanded = true
        }
    }

    func showTranscribing() {
        guard panel.isVisible else { return }
        lifecycle?.cancel()
        stopTimer()
        model.state = .transcribing
        model.isExpanded = true
    }

    func showOutcome(_ state: IndicatorState) {
        guard panel.isVisible else { return }
        lifecycle?.cancel()
        stopTimer()
        model.state = state
        if state == .failed { model.shakeCount += 1 }
        let hold = holdDuration(for: state)
        lifecycle = Task { [weak self] in
            try? await Task.sleep(for: hold)
            guard !Task.isCancelled, let self else { return }
            self.collapseAndHide()
        }
    }

    func shake() {
        guard panel.isVisible else { return }
        model.shakeCount += 1
    }

    func attach(to dictation: Dictation) {
        dictation.onPreview = { [weak self] text in self?.showPreview(text) }
        dictation.onOutcome = { [weak self] outcome in
            switch outcome {
            case .done: self?.showOutcome(.done)
            case .discarded: self?.showOutcome(.discarded)
            case .failed: self?.showOutcome(.failed)
            }
        }
        levelSource = { [weak dictation] in dictation?.inputLevel ?? 0 }
        dictation.onBusy = { [weak self] in self?.shake() }
    }

    func sync(phase: Dictation.Phase) {
        guard phase != lastPhase else { return }
        lastPhase = phase
        switch phase {
        case .recording: showRecording()
        case .transcribing: showTranscribing()
        case .idle: if model.state == .recording || model.state == .transcribing { hide() }
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        lifecycle?.cancel()
        collapseAndHide()
    }

    func showPreview(_ text: String) {
        guard panel.isVisible, model.state == .recording || model.state == .transcribing else { return }
        guard !text.isEmpty else { return clearPreview() }
        model.preview = text
    }

    private func clearPreview() {
        model.preview = ""
    }

    private func startSampling() {
        sampler?.invalidate()
        smoother = LevelSmoother()
        lastSampleTime = Date.now.timeIntervalSinceReferenceDate
        let timer = Timer(timeInterval: Self.sampleInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sampleLevel() }
        }
        RunLoop.main.add(timer, forMode: .common)
        sampler = timer
    }

    private func sampleLevel() {
        let now = Date.now.timeIntervalSinceReferenceDate
        let level = smoother.update(target: levelSource(), elapsedSeconds: now - lastSampleTime)
        lastSampleTime = now
        model.levels.append(level, at: now)
        panel.ignoresMouseEvents = !isMouseOverPreview
    }

    private var isMouseOverPreview: Bool {
        guard !model.preview.isEmpty else { return false }
        let frame = model.previewFrame
        let onScreen = CGRect(x: panel.frame.minX + frame.minX, y: panel.frame.maxY - frame.maxY, width: frame.width, height: frame.height)
        return onScreen.contains(NSEvent.mouseLocation)
    }

    private func stopTimer() {
        sampler?.invalidate()
        sampler = nil
        panel.ignoresMouseEvents = true
        if model.recordingEnd == nil { model.recordingEnd = .now }
    }

    private func holdDuration(for state: IndicatorState) -> Duration {
        switch state {
        case .done: Self.doneHold
        case .discarded: Self.discardHold
        case .failed: Self.failureHold
        case .recording, .transcribing: .zero
        }
    }

    private func collapseAndHide() {
        stopTimer()
        model.isExpanded = false
        lifecycle = Task { [weak self] in
            try? await Task.sleep(for: Self.closeDuration)
            guard !Task.isCancelled, let self else { return }
            self.clearPreview()
            self.panel.orderOut(nil)
            self.panel.contentView = nil
        }
    }

    private func present() {
        guard let screen = ScreenResolver.targetScreen() else {
            Log.app.error("Indicator has no screen to show on")
            return
        }
        model.isExpanded = false
        install(IndicatorLayout.make(visibleFrame: screen.visibleFrame))
        panel.orderFrontRegardless()
    }

    private func repositionIfVisible() {
        guard panel.isVisible, let screen = ScreenResolver.targetScreen() else { return }
        let updated = IndicatorLayout.make(visibleFrame: screen.visibleFrame)
        guard updated != layout else { return }
        install(updated)
    }

    private func install(_ layout: IndicatorLayout) {
        self.layout = layout
        let hosting = NSHostingView(rootView: IndicatorView(model: model, layout: layout))
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.setFrame(layout.windowFrame, display: true)
    }
}

final class IndicatorPanel: NSPanel {
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
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

enum ScreenResolver {
    @MainActor
    static func targetScreen() -> NSScreen? {
        screenOfFrontmostWindow() ?? screenUnderMouse() ?? NSScreen.main ?? NSScreen.screens.first
    }

    @MainActor
    private static func screenOfFrontmostWindow() -> NSScreen? {
        guard
            let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
            let primaryHeight = NSScreen.screens.first?.frame.height,
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        for window in windows {
            guard
                window[kCGWindowOwnerPID as String] as? pid_t == pid,
                window[kCGWindowLayer as String] as? Int == 0,
                let boundsDictionary = window[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDictionary)
            else { continue }
            let cocoaFrame = CGRect(x: bounds.minX, y: primaryHeight - bounds.maxY, width: bounds.width, height: bounds.height)
            let screens = NSScreen.screens
            if let index = ScreenChoice.index(containing: cocoaFrame, in: screens.map(\.frame)) {
                return screens[index]
            }
        }
        return nil
    }

    @MainActor
    private static func screenUnderMouse() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) }
    }
}

@MainActor
enum IndicatorDemo {
    static let launchArgument = "--demo-indicator"

    static func run(on indicator: IndicatorController) async {
        try? await Task.sleep(for: .milliseconds(500))
        let start = Date.now
        indicator.levelSource = {
            let seconds = Date.now.timeIntervalSince(start)
            let envelope = 0.5 + 0.5 * sin(seconds * 2.3)
            let syllables = abs(sin(seconds * 9.5))
            return Float(min(1, envelope * syllables * 1.1))
        }
        indicator.showRecording()
        let words = "This is a live preview of your dictation. Keep speaking and the latest words appear here, without moving your cursor or changing the app you are typing into.".split(separator: " ")
        for count in 1...words.count {
            try? await Task.sleep(for: .milliseconds(140))
            indicator.showPreview(words.prefix(count).joined(separator: " "))
        }
        try? await Task.sleep(for: .seconds(1))
        indicator.showTranscribing()
        try? await Task.sleep(for: .seconds(2))
        indicator.showOutcome(.done)
        try? await Task.sleep(for: .seconds(1.8))
        indicator.showRecording()
        try? await Task.sleep(for: .seconds(1.2))
        indicator.showOutcome(.failed)
        try? await Task.sleep(for: .seconds(1.8))
    }
}
