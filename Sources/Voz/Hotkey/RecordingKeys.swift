@preconcurrency import CoreFoundation
import CoreGraphics
import Foundation

/// A key Voz takes over while you record: Return sends what you said, Esc throws the recording away
enum RecordingKey: Equatable, Sendable {
    case send
    case cancel
}

/// Decides which key presses Voz keeps from the front app while recording
struct RecordingKeyFilter: Equatable, Sendable {
    static let returnKey: UInt16 = 36
    static let keypadEnter: UInt16 = 76
    static let escape: UInt16 = 53

    let hotkey: Hotkey
    let quickSend: Bool

    func key(for keyCode: UInt16, flags: CGEventFlags) -> RecordingKey? {
        guard hotkey.isModifierOnly || keyCode != hotkey.keyCode else { return nil }
        // Holding a modifier hotkey while you press Return still counts, any other modifier means a shortcut
        let extra = flags.intersection(Hotkey.relevantModifiers).subtracting(hotkey.modifiers)
        guard extra.isEmpty else { return nil }
        switch keyCode {
        case Self.escape: return .cancel
        case Self.returnKey, Self.keypadEnter: return quickSend ? .send : nil
        default: return nil
        }
    }
}

/// Lives on the tap's thread and decides there, so Return and Esc never wait for the main thread
private final class RecordingKeyRelay: @unchecked Sendable {
    var port: CFMachPort?
    let filter: RecordingKeyFilter
    let deliver: @Sendable (RecordingKey) -> Void
    /// Key codes whose key down Voz kept, so their key up stays away from the app too
    private var held: Set<UInt16> = []

    init(filter: RecordingKeyFilter, deliver: @escaping @Sendable (RecordingKey) -> Void) {
        self.filter = filter
        self.deliver = deliver
    }

    /// Returns false to keep the event from the front app
    func passes(type: CGEventType, event: CGEvent) -> Bool {
        let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return true
        case .keyDown:
            if held.contains(keyCode) { return false }
            guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0,
                  let key = filter.key(for: keyCode, flags: event.flags) else { return true }
            held.insert(keyCode)
            deliver(key)
            return false
        case .keyUp:
            return held.remove(keyCode) == nil
        default:
            return true
        }
    }
}

/// An event tap that exists only while Voz records, so Return and Esc reach your apps as usual the rest of the time
@MainActor
final class RecordingKeys {
    private var tap: CFMachPort?
    private var relay: RecordingKeyRelay?
    private let onKey: @MainActor (RecordingKey) -> Void

    init(onKey: @escaping @MainActor (RecordingKey) -> Void) {
        self.onKey = onKey
    }

    func start(_ filter: RecordingKeyFilter) {
        guard tap == nil else { return }
        let relay = RecordingKeyRelay(filter: filter) { [weak self] key in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.onKey(key) } }
        }
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let relay = Unmanaged<RecordingKeyRelay>.fromOpaque(userInfo).takeUnretainedValue()
            return relay.passes(type: type, event: event) ? Unmanaged.passUnretained(event) : nil
        }
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(relay).toOpaque()
        ) else {
            Log.app.error("Recording key tap failed, Return and Esc pass through to the app")
            return
        }
        relay.port = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        let thread = Thread {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            withExtendedLifetime(relay) { CFRunLoopRun() }
        }
        thread.name = "voz.recording-keys"
        thread.qualityOfService = .userInteractive
        thread.start()
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.relay = relay
    }

    func stop() {
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        relay = nil
    }
}
