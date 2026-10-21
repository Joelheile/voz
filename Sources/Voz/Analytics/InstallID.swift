import Foundation

struct InstallID {
    static let usage = "installId"
    static let versionPing = "versionPingId"

    let value: UUID
    let isNew: Bool

    init(key: String, defaults: UserDefaults = .standard) {
        if let stored = defaults.string(forKey: key).flatMap(UUID.init) {
            value = stored
            isNew = false
        } else {
            value = UUID()
            isNew = true
            defaults.set(value.uuidString, forKey: key)
        }
    }
}
