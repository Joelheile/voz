import AppKit
import Carbon.HIToolbox

/// Runs extension actions from their hotkeys: chords such as "ctrl+opt+e" through Carbon, and modifier taps such as "rightopt" through an event monitor.
/// Actions that share a hotkey arrive together, so the caller can pick one by its `when`.
@MainActor
final class ActionHotkeys {
    private static let signature: OSType = 0x564F_5A58

    private let run: ([String]) -> Void
    private let dictationKey: () -> Hotkey
    private var handler: EventHandlerRef?
    private var registered: [EventHotKeyRef] = []
    private var chords: [UInt32: [String]] = [:]
    private var taps: [(machine: HotkeyStateMachine, ids: [String])] = []
    private var monitors: [Any] = []

    init(dictationKey: @escaping () -> Hotkey, run: @escaping ([String]) -> Void) {
        self.dictationKey = dictationKey
        self.run = run
    }

    /// Returns the actions whose hotkey can't be used, including taps on the dictation key
    func register(_ list: [ExtensionAction]) -> [ExtensionAction] {
        let dictationKey = dictationKey()
        unregisterAll()
        installHandlerIfNeeded()
        let byHotkey = Dictionary(grouping: list.filter { $0.hotkey != nil }) { $0.hotkey!.lowercased() }
        var unusable: [ExtensionAction] = []
        for (hotkey, actions) in byHotkey {
            let ids = actions.map(\.id)
            if let tap = Hotkey.tap(named: hotkey) {
                guard tap.keyCode != dictationKey.keyCode else { unusable += actions; continue }
                taps.append((HotkeyStateMachine(hotkey: tap), ids))
            } else if !register(hotkey, for: ids) {
                unusable += actions
            }
        }
        if !taps.isEmpty { installMonitors() }
        return unusable
    }

    func unregisterAll() {
        registered.forEach { UnregisterEventHotKey($0) }
        registered = []
        chords = [:]
        taps = []
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
    }

    private func register(_ hotkey: String, for ids: [String]) -> Bool {
        guard let chord = try? KeyChord(parsing: hotkey), let code = chord.keyCode else { return false }
        let number = UInt32(chords.count + 1)
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(code), Self.carbonModifiers(chord.modifiers),
            EventHotKeyID(signature: Self.signature, id: number),
            GetApplicationEventTarget(), 0, &reference
        )
        guard status == noErr, let reference else { return false }
        registered.append(reference)
        chords[number] = ids
        return true
    }

    private func installMonitors() {
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .keyUp, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }) { monitors.append(local) }
    }

    private func handle(_ event: NSEvent) {
        guard let input = Self.input(event) else { return }
        let dictationKey = dictationKey().keyCode
        for index in taps.indices where taps[index].machine.handle(input) == .toggle && taps[index].machine.hotkey.keyCode != dictationKey {
            run(taps[index].ids)
        }
    }

    private static func input(_ event: NSEvent) -> HotkeyInput? {
        let flags = event.cgEvent?.flags ?? []
        switch event.type {
        case .flagsChanged: return .flagsChanged(keyCode: event.keyCode, flags: flags, time: event.timestamp)
        case .keyDown: return .keyDown(keyCode: event.keyCode, flags: flags, time: event.timestamp, isRepeat: event.isARepeat)
        case .keyUp: return .keyUp(keyCode: event.keyCode, time: event.timestamp)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown: return .pointerDown
        default: return nil
        }
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var hotkey = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotkey)
            let hotkeys = Unmanaged<ActionHotkeys>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { hotkeys.pressed(hotkey.id) }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    private func pressed(_ number: UInt32) {
        guard let ids = chords[number] else { return }
        run(ids)
    }

    private static func carbonModifiers(_ modifiers: KeyChord.Modifiers) -> UInt32 {
        var flags = 0
        if modifiers.contains(.command) { flags |= cmdKey }
        if modifiers.contains(.shift) { flags |= shiftKey }
        if modifiers.contains(.option) { flags |= optionKey }
        if modifiers.contains(.control) { flags |= controlKey }
        return UInt32(flags)
    }
}
