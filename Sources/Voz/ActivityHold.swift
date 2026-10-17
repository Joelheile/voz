import Foundation

@MainActor
final class ActivityHold {
    private var token: NSObjectProtocol?

    func set(held: Bool) {
        switch (held, token) {
        case (true, nil):
            token = ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: "voz dictation")
        case (false, let token?):
            ProcessInfo.processInfo.endActivity(token)
            self.token = nil
        default:
            break
        }
    }
}
