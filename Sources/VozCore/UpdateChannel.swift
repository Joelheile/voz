public enum UpdateChannel: String, Sendable {
    case stable
    case beta

    public init(version: String) {
        self = version.contains("-beta") ? .beta : .stable
    }
}
