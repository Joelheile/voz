import CoreGraphics
import Foundation
import VozCore

@MainActor
final class HotkeyMonitor {
    private var machine: HotkeyStateMachine
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var healthTimer: Timer?
    private let isRecording: @MainActor () -> Bool
    private let onAction: @MainActor (HotkeyAction) -> Void

    var isRunning: Bool { tap != nil }

    init(
        hotkey: Hotkey,
        holdToTalk: Bool,
        isRecording: @escaping @MainActor () -> Bool,
        onAction: @escaping @MainActor (HotkeyAction) -> Void
    ) {
        machine = HotkeyStateMachine(hotkey: hotkey, holdToTalk: holdToTalk)
        self.isRecording = isRecording
        self.onAction = onAction
    }

    func configure(hotkey: Hotkey, holdToTalk: Bool) {
        machine.configure(hotkey: hotkey, holdToTalk: holdToTalk)
    }

    func start() -> Bool {
        guard tap == nil else { return true }
        let mask: CGEventMask = [
            CGEventType.flagsChanged, .keyDown, .keyUp, .leftMouseDown, .rightMouseDown, .otherMouseDown,
        ].reduce(0) { $0 | (1 << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.handle(type: type, event: event) }
            return Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        runLoopSource = source
        return true
    }

    func stop() {
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        runLoopSource = nil
    }

    func recreate() {
        machine.reset()
        stop()
        let started = start()
        Log.app.notice("Event tap recreated: \(started)")
    }

    func reset() {
        machine.reset()
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    func startHealthChecks(interval: TimeInterval = 30) {
        healthTimer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkHealth() }
        }
        timer.tolerance = interval / 6
        RunLoop.main.add(timer, forMode: .common)
        healthTimer = timer
    }

    func checkHealth() {
        let isEnabled = tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false
        var enableSucceeded = false
        if let tap, !isEnabled {
            CGEvent.tapEnable(tap: tap, enable: true)
            enableSucceeded = CGEvent.tapIsEnabled(tap: tap)
        }
        let action = TapHealthAction.decide(
            accessibilityGranted: Permissions.accessibilityGranted,
            hasTap: tap != nil,
            isEnabled: isEnabled,
            enableSucceeded: enableSucceeded
        )
        switch action {
        case .none, .enable:
            break
        case .stop:
            Log.app.warning("Accessibility revoked, event tap stopped")
            stop()
        case .create:
            let started = start()
            Log.app.notice("Accessibility available, event tap created: \(started)")
        case .recreate:
            Log.app.warning("Event tap could not be re-enabled, recreating")
            recreate()
        }
    }

    private func handle(type: CGEventType, event: CGEvent) {
        let time = ProcessInfo.processInfo.systemUptime
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let input: HotkeyInput
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            Log.app.warning("Event tap disabled, re-enabling")
            reset()
            return
        case .flagsChanged:
            input = .flagsChanged(keyCode: keyCode, flags: event.flags, time: time)
        case .keyDown:
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            input = .keyDown(keyCode: keyCode, flags: event.flags, time: time, isRepeat: isRepeat)
        case .keyUp:
            input = .keyUp(keyCode: keyCode, time: time)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            input = .pointerDown
        default:
            return
        }
        let action = machine.handle(input, isRecording: isRecording())
        if action != .none { onAction(action) }
    }
}
