import CoreGraphics

public enum KeyChordError: Error, Equatable {
    case unknownKey(String)
    case unknownModifier(String)
}

public struct KeyChord: Equatable, Sendable {
    public enum Key: Equatable, Sendable {
        case code(UInt16)
        case character(String)
    }

    public struct Modifiers: OptionSet, Equatable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let command = Modifiers(rawValue: 1 << 0)
        public static let shift = Modifiers(rawValue: 1 << 1)
        public static let option = Modifiers(rawValue: 1 << 2)
        public static let control = Modifiers(rawValue: 1 << 3)

        public var eventFlags: CGEventFlags {
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

    public let key: Key
    public let modifiers: Modifiers
    public let label: String

    public var keyCode: UInt16? {
        switch key {
        case .code(let code): code
        case .character(let character): KeyboardLayout.keyCode(producing: character)
        }
    }

    public init(parsing raw: String) throws(KeyChordError) {
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
