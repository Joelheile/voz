public enum UpdateChannel: String, AnalyticsLabel {
    case stable
    case beta

    public init(version: String) {
        self = version.contains("-beta") ? .beta : .stable
    }
}
