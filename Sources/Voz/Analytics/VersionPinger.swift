import Foundation
import VozCore

enum VersionPinger {
    private static let endpoint = URL(string: "\(Analytics.host)/i/v0/e/")!

    static func send(_ ping: VersionPing, version: String) {
        Task.detached(priority: .background) {
            do {
                var request = URLRequest(url: endpoint)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try ping.body(version: version, projectToken: Analytics.projectToken)
                let (_, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status != 200 { Log.app.error("Version ping returned status \(status)") }
            } catch {
                Log.app.error("Version ping failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
