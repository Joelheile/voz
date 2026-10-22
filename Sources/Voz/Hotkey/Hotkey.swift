import Carbon.HIToolbox
import CoreGraphics
import Foundation

struct Hotkey: Hashable, Sendable, Codable {
    static let relevantModifiers: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
    static let chordModifiers: CGEventFlags = relevantModifiers.union(.maskSecondaryFn)
    static let rightCommand = Hotkey(keyCode: 54, modifiers: .maskCommand)

    private static let modifierFlags: [UInt16: CGEventFlags] = [
        54: .maskCommand, 55: .maskCommand,
        56: .maskShift, 60: .maskShift,
        58: .maskAlternate, 61: .maskAlternate,
        59: .maskControl, 62: .maskControl,
        63: .maskSecondaryFn,
    ]

    let keyCode: UInt16
    let modifiers: CGEventFlags

    init(keyCode: UInt16, modifiers: CGEventFlags) {
        self.keyCode = keyCode
        if let ownFlag = Hotkey.modifierFlags[keyCode] {
            self.modifiers = modifiers.intersection(Hotkey.chordModifiers).union(ownFlag)
        } else {
            self.modifiers = modifiers.intersection(Hotkey.relevantModifiers)
        }
    }

    var isModifierOnly: Bool {
        ownModifierFlag != nil
    }

    var isChord: Bool {
        guard let ownModifierFlag else { return false }
        return !modifiers.subtracting(ownModifierFlag).isEmpty
    }

    var ownModifierFlag: CGEventFlags? {
        Hotkey.modifierFlags[keyCode]
    }

    var matchedModifiers: CGEventFlags {
        Hotkey.relevantModifiers.union(modifiers.intersection(.maskSecondaryFn))
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(keyCode)
        hasher.combine(modifiers.rawValue)
    }

    private enum CodingKeys: String, CodingKey {
        case keyCode
        case modifiers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            keyCode: try container.decode(UInt16.self, forKey: .keyCode),
            modifiers: CGEventFlags(rawValue: try container.decode(UInt64.self, forKey: .modifiers))
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keyCode, forKey: .keyCode)
        try container.encode(modifiers.rawValue, forKey: .modifiers)
    }
}

extension Hotkey {
    private static let modifierKeyNames: [UInt16: String] = [
        54: "Right ⌘", 55: "Left ⌘",
        56: "Left ⇧", 60: "Right ⇧",
        58: "Left ⌥", 61: "Right ⌥",
        59: "Left ⌃", 62: "Right ⌃",
        63: "Fn",
    ]

    private static let keyNames: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2",
        20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8",
        29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "Return",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N",
        46: "M", 47: ".", 48: "Tab", 49: "Space", 50: "`", 51: "Delete", 53: "Esc",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11",
        105: "F13", 107: "F14", 109: "F10", 111: "F12", 113: "F15", 118: "F4", 120: "F2",
        122: "F1", 114: "Help", 115: "Home", 116: "Page Up", 117: "Forward Delete",
        119: "End", 121: "Page Down", 123: "←", 124: "→", 125: "↓", 126: "↑",
    ]

    var displayName: String {
        if isChord { return modifierSymbols }
        if let name = Hotkey.modifierKeyNames[keyCode] { return name }
        let key = Hotkey.keyNames[keyCode] ?? "Key \(keyCode)"
        return modifierSymbols + key
    }

    private var modifierSymbols: String {
        var symbols = modifiers.contains(.maskSecondaryFn) ? "fn " : ""
        if modifiers.contains(.maskControl) { symbols += "⌃" }
        if modifiers.contains(.maskAlternate) { symbols += "⌥" }
        if modifiers.contains(.maskShift) { symbols += "⇧" }
        if modifiers.contains(.maskCommand) { symbols += "⌘" }
        return symbols
    }
}

enum SystemShortcuts {
    private static let reserved: [Hotkey: String] = [
        Hotkey(keyCode: 49, modifiers: .maskCommand): "Spotlight",
        Hotkey(keyCode: 48, modifiers: .maskCommand): "the app switcher",
        Hotkey(keyCode: 12, modifiers: .maskCommand): "Quit",
        Hotkey(keyCode: 13, modifiers: .maskCommand): "Close Window",
        Hotkey(keyCode: 8, modifiers: .maskCommand): "Copy",
        Hotkey(keyCode: 9, modifiers: .maskCommand): "Paste",
        Hotkey(keyCode: 49, modifiers: .maskControl): "input source switching",
    ]

    static func warning(for hotkey: Hotkey) -> String? {
        reserved[hotkey].map { "\(hotkey.displayName) is a system shortcut for \($0). It also triggers that action." }
    }
}

enum KeyChordError: Error, Equatable {
    case unknownKey(String)
    case unknownModifier(String)
}

struct KeyChord: Equatable, Sendable {
    enum Key: Equatable, Sendable {
        case code(UInt16)
        case character(String)
    }

    struct Modifiers: OptionSet, Equatable, Sendable {
        let rawValue: Int
        init(rawValue: Int) { self.rawValue = rawValue }

        static let command = Modifiers(rawValue: 1 << 0)
        static let shift = Modifiers(rawValue: 1 << 1)
        static let option = Modifiers(rawValue: 1 << 2)
        static let control = Modifiers(rawValue: 1 << 3)

        var eventFlags: CGEventFlags {
            var flags: CGEventFlags = []
            if contains(.command) { flags.insert(.maskCommand) }
            if contains(.shift) { flags.insert(.maskShift) }
            if contains(.option) { flags.insert(.maskAlternate) }
            if contains(.control) { flags.insert(.maskControl) }
            return flags
        }
    }

    private static let namedKeys: [String: UInt16] = [
        "return": 36, "enter": 36, "tab": 48, "space": 49, "delete": 51, "backspace": 51, "escape": 53, "esc": 53,
        "forwarddelete": 117, "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
        "left": 123, "right": 124, "down": 125, "up": 126,
    ]

    private static let modifierNames: [String: Modifiers] = [
        "cmd": .command, "command": .command, "shift": .shift,
        "opt": .option, "option": .option, "alt": .option, "ctrl": .control, "control": .control,
    ]

    private static let keySymbols: [String: String] = [
        "return": "↩", "enter": "↩", "tab": "⇥", "space": "Space", "delete": "⌫", "backspace": "⌫", "escape": "⎋", "esc": "⎋",
        "forwarddelete": "⌦", "home": "↖", "end": "↘", "pageup": "⇞", "pagedown": "⇟",
        "left": "←", "right": "→", "down": "↓", "up": "↑",
    ]

    let key: Key
    let modifiers: Modifiers
    let label: String

    var keyCode: UInt16? {
        switch key {
        case .code(let code): code
        case .character(let character): KeyboardLayout.keyCode(producing: character)
        }
    }

    init(parsing raw: String) throws(KeyChordError) {
        let parts = raw.lowercased().split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        let keyName = parts.last ?? ""
        var modifiers: Modifiers = []
        for name in parts.dropLast() {
            guard let modifier = Self.modifierNames[name] else { throw .unknownModifier(name) }
            modifiers.insert(modifier)
        }
        if let code = Self.namedKeys[keyName] {
            key = .code(code)
        } else if keyName.count == 1 {
            key = .character(keyName)
        } else {
            throw .unknownKey(keyName)
        }
        self.modifiers = modifiers
        label = Self.symbols(for: modifiers) + (Self.keySymbols[keyName] ?? keyName.uppercased())
    }

    private static func symbols(for modifiers: Modifiers) -> String {
        [(Modifiers.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
            .filter { modifiers.contains($0.0) }
            .map(\.1)
            .joined()
    }
}

enum KeyboardLayout {
    private static let keyCount: UInt16 = 128

    static func keyCode(producing character: String) -> UInt16? {
        guard
            let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
            let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
        return layoutData.withUnsafeBytes { raw -> UInt16? in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            return (0..<Self.keyCount).first { translate(keyCode: $0, layout: layout) == character }
        }
    }

    private static func translate(keyCode: UInt16, layout: UnsafePointer<UCKeyboardLayout>) -> String? {
        var deadKeys: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = UCKeyTranslate(
            layout, keyCode, UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, characters.count, &length, &characters
        )
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }
}

enum DictationHint {
    static func idle(hotkey: Hotkey, holdToTalk: Bool) -> String {
        "\(verb(hotkey: hotkey, holdToTalk: holdToTalk)) \(key(hotkey)) to dictate"
    }

    static func recording(hotkey: Hotkey, holdToTalk: Bool) -> String {
        holdToTalk
            ? "Release \(key(hotkey)) to stop"
            : "\(verb(hotkey: hotkey, holdToTalk: false)) \(key(hotkey)) again to stop"
    }

    private static func verb(hotkey: Hotkey, holdToTalk: Bool) -> String {
        if holdToTalk { return "Hold" }
        return hotkey.isModifierOnly ? "Tap" : "Press"
    }

    static func key(_ hotkey: Hotkey) -> String {
        let name = hotkey.displayName
        for side in ["Left ", "Right "] where name.hasPrefix(side) {
            return side.lowercased() + name.dropFirst(side.count)
        }
        return name
    }
}
