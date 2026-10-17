public enum UpdateDetector {
    public static func installedUpdate(previousVersion: String?, currentVersion: String) -> AnalyticsEvent? {
        guard let previousVersion, previousVersion != currentVersion else { return nil }
        return .updateInstalled(from: previousVersion, to: currentVersion, channel: UpdateChannel(version: currentVersion))
    }
}
