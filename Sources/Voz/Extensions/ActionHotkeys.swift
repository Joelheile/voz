import Carbon.HIToolbox
import VozCore

@MainActor
final class ActionHotkeys {
    private static let signature: OSType = 0x564F_5A58

    private let run: (String) -> Void
    private var handler: EventHandlerRef?
    private var registered: [EventHotKeyRef] = []
    private var actions: [UInt32: String] = [:]

    init(run: @escaping (String) -> Void) {
        self.run = run
    }

    func register(_ list: [ExtensionAction]) -> [ExtensionAction] {
        unregisterAll()
        installHandlerIfNeeded()
        return list.filter { action in
            guard let hotkey = action.hotkey else { return false }
            return !register(hotkey, for: action.id)
        }
    }

    func unregisterAll() {
        registered.forEach { UnregisterEventHotKey($0) }
        registered = []
        actions = [:]
    }

    private func register(_ hotkey: String, for id: String) -> Bool {
        guard let chord = try? KeyChord(parsing: hotkey), let code = chord.keyCode else { return false }
        let number = UInt32(actions.count + 1)
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(code), Self.carbonModifiers(chord.modifiers),
            EventHotKeyID(signature: Self.signature, id: number),
            GetApplicationEventTarget(), 0, &reference
        )
        guard status == noErr, let reference else { return false }
        registered.append(reference)
        actions[number] = id
        return true
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
        guard let id = actions[number] else { return }
        run(id)
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
