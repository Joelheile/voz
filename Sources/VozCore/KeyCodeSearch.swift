public enum KeyCodeSearch {
    public static let keyCount: UInt16 = 128

    public static func keyCode(producing character: String, translate: (UInt16) -> String?) -> UInt16? {
        (0..<keyCount).first { translate($0) == character }
    }
}
