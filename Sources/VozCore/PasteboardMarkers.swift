public enum PasteboardMarkers {
    public static let transient = "org.nspasteboard.TransientType"
    public static let concealed = "org.nspasteboard.ConcealedType"

    public static func types(copyToClipboard: Bool) -> [String] {
        copyToClipboard ? [] : [transient, concealed]
    }
}
