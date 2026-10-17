import Foundation

struct InstallID {
    private static let key = "installId"

    let value: UUID
    let isNew: Bool

    init(defaults: UserDefaults = .standard) {
        if let stored = defaults.string(forKey: Self.key).flatMap(UUID.init) {
            value = stored
            isNew = false
        } else {
            value = UUID()
            isNew = true
            defaults.set(value.uuidString, forKey: Self.key)
        }
    }
}
