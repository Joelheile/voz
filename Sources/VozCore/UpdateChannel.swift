public enum UpdateChannel: String, Sendable {
    case stable
    case beta
    case dev

    public init(version: String) {
        if version.contains("-dev") {
            self = .dev
        } else {
            self = version.contains("-beta") ? .beta : .stable
        }
    }
}
