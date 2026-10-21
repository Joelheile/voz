import Foundation
import VozCore

@MainActor
enum VersionPinger {
    private static let endpoint = URL(string: "\(Analytics.host)/i/v0/e/")!

    static func sendPending(_ ping: VersionPing?, launch: LaunchVersion, enabled: Bool) {
        do {
            let queue = try VersionPingQueue()
            guard enabled, UpdateChannel(version: launch.current) != .dev else { return try queue.clear() }
            if let ping {
                let pingID = InstallID(key: InstallID.versionPing).value
                try queue.enqueue(ping, version: launch.current, previous: launch.updatedFrom, pingID: pingID, projectToken: Analytics.projectToken)
            }
            Task {
                do {
                    for body in queue.pending {
                        guard UserDefaults.standard.bool(forKey: "versionPingEnabled") else {
                            try queue.clear()
                            return
                        }
                        if try await send(body) { try queue.acknowledge(body) }
                    }
                } catch {
                    Log.app.error("Version ping retry stopped: \(error.localizedDescription, privacy: .public)")
                }
            }
        } catch {
            Log.app.error("Version ping queue failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func send(_ body: Data) async throws -> Bool {
        for attempt in 1...3 {
            guard UserDefaults.standard.bool(forKey: "versionPingEnabled") else { return false }
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 15
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if (200..<300).contains(status) { return true }
                Log.app.error("Version ping attempt \(attempt) returned status \(status), retained for retry")
            } catch let error as URLError {
                Log.app.error("Version ping attempt \(attempt) failed, retained for retry: \(error.localizedDescription, privacy: .public)")
            }
            if attempt < 3 { try await Task.sleep(for: .seconds(attempt * 5)) }
        }
        return false
    }
}
