import CoreGraphics

public struct Hotkey: Hashable, Sendable, Codable {
    public static let relevantModifiers: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
    public static let chordModifiers: CGEventFlags = relevantModifiers.union(.maskSecondaryFn)
    public static let rightCommand = Hotkey(keyCode: 54, modifiers: .maskCommand)

    private static let modifierFlags: [UInt16: CGEventFlags] = [
        54: .maskCommand, 55: .maskCommand,
        56: .maskShift, 60: .maskShift,
        58: .maskAlternate, 61: .maskAlternate,
        59: .maskControl, 62: .maskControl,
        63: .maskSecondaryFn,
    ]

    public let keyCode: UInt16
    public let modifiers: CGEventFlags

    public init(keyCode: UInt16, modifiers: CGEventFlags) {
        self.keyCode = keyCode
        if let ownFlag = Hotkey.modifierFlags[keyCode] {
            self.modifiers = modifiers.intersection(Hotkey.chordModifiers).union(ownFlag)
        } else {
            self.modifiers = modifiers.intersection(Hotkey.relevantModifiers)
        }
    }

    public var isModifierOnly: Bool {
        Hotkey.modifierFlags[keyCode] != nil
    }

    public var isChord: Bool {
        guard let ownModifierFlag else { return false }
        return !modifiers.subtracting(ownModifierFlag).isEmpty
    }

    public var ownModifierFlag: CGEventFlags? {
        Hotkey.modifierFlags[keyCode]
    }

    public var matchedModifiers: CGEventFlags {
        Hotkey.relevantModifiers.union(modifiers.intersection(.maskSecondaryFn))
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(keyCode)
        hasher.combine(modifiers.rawValue)
    }

    private enum CodingKeys: String, CodingKey {
        case keyCode
        case modifiers
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            keyCode: try container.decode(UInt16.self, forKey: .keyCode),
            modifiers: CGEventFlags(rawValue: try container.decode(UInt64.self, forKey: .modifiers))
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keyCode, forKey: .keyCode)
        try container.encode(modifiers.rawValue, forKey: .modifiers)
    }
}
