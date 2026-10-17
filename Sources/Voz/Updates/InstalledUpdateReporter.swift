import Foundation
import VozCore

struct InstalledUpdateReporter {
    private static let key = "lastLaunchedVersion"

    let defaults: UserDefaults

    func event(currentVersion: String) -> AnalyticsEvent? {
        let previous = defaults.string(forKey: Self.key)
        defaults.set(currentVersion, forKey: Self.key)
        return UpdateDetector.installedUpdate(previousVersion: previous, currentVersion: currentVersion)
    }
}
