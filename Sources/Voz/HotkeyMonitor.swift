@preconcurrency import CoreFoundation
import CoreGraphics
import Foundation
import VozCore

private final class TapRelay: @unchecked Sendable {
    var port: CFMachPort?
    let deliver: @Sendable (HotkeyInput) -> Void
    let disabled: @Sendable () -> Void

    init(deliver: @escaping @Sendable (HotkeyInput) -> Void, disabled: @escaping @Sendable () -> Void) {
        self.deliver = deliver
        self.disabled = disabled
    }

    func handle(type: CGEventType, event: CGEvent) {
        let time = ProcessInfo.processInfo.systemUptime
        let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            disabled()
        case .flagsChanged:
            deliver(.flagsChanged(keyCode: keyCode, flags: event.flags, time: time))
        case .keyDown:
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            deliver(.keyDown(keyCode: keyCode, flags: event.flags, time: time, isRepeat: isRepeat))
        case .keyUp:
            deliver(.keyUp(keyCode: keyCode, time: time))
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            deliver(.pointerDown)
        default:
            break
        }
    }
}

@MainActor
final class HotkeyMonitor {
    private static let healthyTapCheckInterval = 30.0
    private static let missingTapCheckInterval = 2.0

    private var machine: HotkeyStateMachine
    private var tap: CFMachPort?
    private var relay: TapRelay?
    private var healthTimer: Timer?
    private let isRecording: @MainActor () -> Bool
    private let onAction: @MainActor (HotkeyAction) -> Void

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
        let relay = TapRelay(
            deliver: { [weak self] input in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.handle(input) } }
            },
            disabled: { [weak self] in
                Log.app.warning("Event tap disabled, re-enabled")
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.machine.reset() } }
            }
        )
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            if let userInfo {
                Unmanaged<TapRelay>.fromOpaque(userInfo).takeUnretainedValue().handle(type: type, event: event)
            }
            return Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(relay).toOpaque()
        ) else {
            return false
        }
        relay.port = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        let thread = Thread {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            withExtendedLifetime(relay) { CFRunLoopRun() }
        }
        thread.name = "voz.hotkey-tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.relay = relay
        return true
    }

    func stop() {
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        relay = nil
    }

    func recreate() {
        machine.reset()
        stop()
        let started = start()
        Log.app.notice("Event tap recreated: \(started)")
    }

    func startHealthChecks() {
        checkHealth()
    }

    func checkHealth() {
        defer { scheduleNextHealthCheck() }
        guard Permissions.accessibilityGranted else {
            guard tap != nil else { return }
            Log.app.warning("Accessibility revoked, event tap stopped")
            stop()
            return
        }
        guard let tap else {
            if start() { Log.app.notice("Hotkey tap started") }
            return
        }
        guard !CGEvent.tapIsEnabled(tap: tap) else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
        guard !CGEvent.tapIsEnabled(tap: tap) else { return }
        Log.app.warning("Event tap could not be re-enabled, recreating")
        recreate()
    }

    private func scheduleNextHealthCheck() {
        healthTimer?.invalidate()
        let interval = tap == nil ? Self.missingTapCheckInterval : Self.healthyTapCheckInterval
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkHealth() }
        }
        timer.tolerance = interval / 6
        RunLoop.main.add(timer, forMode: .common)
        healthTimer = timer
    }

    private func handle(_ input: HotkeyInput) {
        let action = machine.handle(input, isRecording: isRecording())
        if action != .none { onAction(action) }
    }
}
