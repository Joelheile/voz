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
    /// Set once, before the first filter
    var port: CFMachPort?
    private let lock = NSLock()
    private var filter: RecordingKeyFilter?
    /// Key codes whose key down Voz kept, so their key up stays away from the app too
    private var held: Set<UInt16> = []
    private let deliver: @Sendable (RecordingKey) -> Void

    init(deliver: @escaping @Sendable (RecordingKey) -> Void) {
        self.deliver = deliver
    }

    /// Nil stops taking keys. Returns false when macOS refuses to turn the tap on, as it does after Accessibility was revoked
    func take(_ filter: RecordingKeyFilter?) -> Bool {
        lock.withLock {
            self.filter = filter
            return syncTap()
        }
    }

    /// The tap outlives the recording until the keys it kept are released, because the recording ends on their key down
    @discardableResult
    private func syncTap() -> Bool {
        guard let port else { return false }
        let wanted = filter != nil || !held.isEmpty
        CGEvent.tapEnable(tap: port, enable: wanted)
        return CGEvent.tapIsEnabled(tap: port) == wanted
    }

    /// Returns false to keep the event from the front app
    func passes(type: CGEventType, event: CGEvent) -> Bool {
        let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        return lock.withLock {
            switch type {
            case .tapDisabledByTimeout, .tapDisabledByUserInput:
                held = []
                syncTap()
                return true
            case .keyDown:
                if held.contains(keyCode) { return false }
                guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0,
                      let key = filter?.key(for: keyCode, flags: event.flags) else { return true }
                held.insert(keyCode)
                deliver(key)
                return false
            case .keyUp:
                guard held.remove(keyCode) != nil else { return true }
                syncTap()
                return false
            default:
                return true
            }
        }
    }
}

/// An event tap that is on only while Voz records, so Return and Esc reach your apps as usual the rest of the time
@MainActor
final class RecordingKeys {
    private var relay: RecordingKeyRelay?
    private let onKey: @MainActor (RecordingKey) -> Void

    init(onKey: @escaping @MainActor (RecordingKey) -> Void) {
        self.onKey = onKey
    }

    func start(_ filter: RecordingKeyFilter) {
        if relay?.take(filter) == true { return }
        if let port = relay?.port { CFMachPortInvalidate(port) }
        relay = makeTap()
        if relay?.take(filter) != true { Log.app.error("Recording key tap failed, Return and Esc pass through to the app") }
    }

    func stop() {
        _ = relay?.take(nil)
    }

    private func makeTap() -> RecordingKeyRelay? {
        let relay = RecordingKeyRelay { [weak self] key in
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
        ) else { return nil }
        CGEvent.tapEnable(tap: tap, enable: false)
        relay.port = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        let thread = Thread {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            withExtendedLifetime(relay) { CFRunLoopRun() }
        }
        thread.name = "voz.recording-keys"
        thread.qualityOfService = .userInteractive
        thread.start()
        return relay
    }
}
