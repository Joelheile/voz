import CoreGraphics

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

    public var displayName: String {
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

public enum SystemShortcuts {
    private static let reserved: [Hotkey: String] = [
        Hotkey(keyCode: 49, modifiers: .maskCommand): "Spotlight",
        Hotkey(keyCode: 48, modifiers: .maskCommand): "the app switcher",
        Hotkey(keyCode: 12, modifiers: .maskCommand): "Quit",
        Hotkey(keyCode: 13, modifiers: .maskCommand): "Close Window",
        Hotkey(keyCode: 8, modifiers: .maskCommand): "Copy",
        Hotkey(keyCode: 9, modifiers: .maskCommand): "Paste",
        Hotkey(keyCode: 49, modifiers: .maskControl): "input source switching",
    ]

    public static func warning(for hotkey: Hotkey) -> String? {
        reserved[hotkey].map { "\(hotkey.displayName) is a system shortcut for \($0). It also triggers that action." }
    }
}
