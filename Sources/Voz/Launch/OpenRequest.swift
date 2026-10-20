import Foundation

enum OpenRequest {
    private static let name = Notification.Name("com.joelheile.voz.open")
    private static let pendingKey = "openPanelOnNextLaunch"

    static func send() {
        DistributedNotificationCenter.default().postNotificationName(name, object: nil, userInfo: nil, deliverImmediately: true)
    }

    @MainActor
    static func observe(_ handler: @escaping @MainActor () -> Void) {
        DistributedNotificationCenter.default().addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated(handler)
        }
    }

    static func deferToNextLaunch() {
        UserDefaults.standard.set(true, forKey: pendingKey)
    }

    static func takePending() -> Bool {
        defer { UserDefaults.standard.removeObject(forKey: pendingKey) }
        return UserDefaults.standard.bool(forKey: pendingKey)
    }
}
