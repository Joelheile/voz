import Foundation

final class SingleInstance {
    private var descriptor: Int32 = -1

    func claim(waiting: Duration) -> Bool {
        let path: String
        do {
            path = try AppStorage.directory().appendingPathComponent("instance.lock").path
        } catch {
            Log.app.error("Instance lock unavailable: \(error.localizedDescription, privacy: .public)")
            return true
        }
        descriptor = open(path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else {
            Log.app.error("Instance lock unavailable, errno \(errno)")
            return true
        }
        let deadline = ContinuousClock.now + waiting
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            guard ContinuousClock.now < deadline else {
                close(descriptor)
                descriptor = -1
                return false
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return true
    }
}
