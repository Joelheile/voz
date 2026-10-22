public enum DictationHint {
    public static func idle(hotkey: Hotkey, holdToTalk: Bool) -> String {
        "\(verb(hotkey: hotkey, holdToTalk: holdToTalk)) \(key(hotkey)) to dictate"
    }

    public static func recording(hotkey: Hotkey, holdToTalk: Bool) -> String {
        holdToTalk
            ? "Release \(key(hotkey)) to stop"
            : "\(verb(hotkey: hotkey, holdToTalk: false)) \(key(hotkey)) again to stop"
    }

    private static func verb(hotkey: Hotkey, holdToTalk: Bool) -> String {
        if holdToTalk { return "Hold" }
        return hotkey.isModifierOnly ? "Tap" : "Press"
    }

    public static func key(_ hotkey: Hotkey) -> String {
        let name = hotkey.displayName
        for side in ["Left ", "Right "] where name.hasPrefix(side) {
            return side.lowercased() + name.dropFirst(side.count)
        }
        return name
    }
}
