public enum DictationHint {
    public static func idle(hotkey: Hotkey, holdToTalk: Bool) -> String {
        "\(verb(hotkey: hotkey, holdToTalk: holdToTalk)) \(keyPhrase(hotkey)) to dictate"
    }

    public static func recording(hotkey: Hotkey, holdToTalk: Bool) -> String {
        holdToTalk
            ? "Release \(keyPhrase(hotkey)) to finish"
            : "\(verb(hotkey: hotkey, holdToTalk: false)) \(keyPhrase(hotkey)) again to finish"
    }

    public static func instruction(hotkey: Hotkey, holdToTalk: Bool) -> String {
        holdToTalk
            ? "Hold \(keyPhrase(hotkey)), say something, then release."
            : "\(verb(hotkey: hotkey, holdToTalk: false)) \(keyPhrase(hotkey)), say something, then \(verb(hotkey: hotkey, holdToTalk: false).lowercased()) it again."
    }

    private static func verb(hotkey: Hotkey, holdToTalk: Bool) -> String {
        if holdToTalk { return "Hold" }
        return hotkey.isModifierOnly ? "Tap" : "Press"
    }

    private static func keyPhrase(_ hotkey: Hotkey) -> String {
        let name = hotkey.displayName
        for side in ["Left ", "Right "] where name.hasPrefix(side) {
            return side.lowercased() + name.dropFirst(side.count)
        }
        return name
    }
}
