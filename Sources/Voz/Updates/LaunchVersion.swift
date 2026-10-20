import Foundation

struct LaunchVersion {
    private static let key = "lastLaunchedVersion"

    let current: String
    let updatedFrom: String?

    static func record(_ current: String, in defaults: UserDefaults) -> LaunchVersion {
        let previous = defaults.string(forKey: key)
        defaults.set(current, forKey: key)
        return LaunchVersion(current: current, updatedFrom: previous == current ? nil : previous)
    }
}
