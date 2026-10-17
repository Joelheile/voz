import AppKit
import SwiftUI
import VozCore

@MainActor
final class IndicatorController {
    private static let doneHold = Duration.milliseconds(600)
    private static let discardHold = Duration.milliseconds(250)
    private static let failureHold = Duration.milliseconds(700)
    private static let closeDuration = Duration.milliseconds(500)

    private let model = IndicatorModel()
    private let panel = IndicatorPanel()
    private var layout: IndicatorLayout?
    private var requestedStyle = IndicatorStyle.notch
    private var lifecycle: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var lastPhase = Dictation.Phase.idle

    init() {
        let reposition: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.repositionIfVisible() }
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main, using: reposition))
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: reposition))
    }

    var isVisible: Bool { panel.isVisible }

    func showRecording() {
        lifecycle?.cancel()
        if !panel.isVisible { present() }
        model.level = 0
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
        model.state = .transcribing
        model.isExpanded = true
    }

    func showOutcome(_ state: IndicatorState) {
        guard panel.isVisible else { return }
        lifecycle?.cancel()
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
        let previousOnChange = dictation.onChange
        dictation.onChange = { [weak self, weak dictation] in
            previousOnChange()
            guard let self, let dictation else { return }
            self.sync(phase: dictation.phase)
        }
        dictation.onOutcome = { [weak self] outcome in
            switch outcome {
            case .done: self?.showOutcome(.done)
            case .discarded: self?.showOutcome(.discarded)
            case .failed: self?.showOutcome(.failed)
            }
        }
        dictation.onLevel = { [weak self] level in self?.pushLevel(level) }
        dictation.onBusy = { [weak self] in self?.shake() }
    }

    private func sync(phase: Dictation.Phase) {
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

    func pushLevel(_ level: Float) {
        guard model.state == .recording else { return }
        model.level = level
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
        model.isExpanded = false
        lifecycle = Task { [weak self] in
            try? await Task.sleep(for: Self.closeDuration)
            guard !Task.isCancelled, let self else { return }
            self.panel.orderOut(nil)
            self.panel.contentView = nil
        }
    }

    private func present() {
        guard let screen = ScreenResolver.targetScreen() else {
            Log.app.error("Indicator has no screen to show on")
            return
        }
        let style = UserDefaults.standard.string(forKey: SettingsKey.indicatorStyle).flatMap(IndicatorStyle.init) ?? .notch
        let layout = IndicatorLayout.make(style: style, screen: ScreenResolver.metrics(for: screen))
        self.layout = layout
        requestedStyle = style
        model.isExpanded = false
        let hosting = NSHostingView(rootView: IndicatorView(model: model, layout: layout))
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.setFrame(layout.panelFrame, display: true)
        panel.orderFrontRegardless()
    }

    private func repositionIfVisible() {
        guard panel.isVisible, let screen = ScreenResolver.targetScreen() else { return }
        let updated = IndicatorLayout.make(style: requestedStyle, screen: ScreenResolver.metrics(for: screen))
        guard updated != layout else { return }
        layout = updated
        panel.contentView = NSHostingView(rootView: IndicatorView(model: model, layout: updated))
        (panel.contentView as? NSHostingView<IndicatorView>)?.sizingOptions = []
        panel.setFrame(updated.panelFrame, display: true)
    }
}
