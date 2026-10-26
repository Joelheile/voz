import Foundation

enum VersionPing: String, Sendable, Encodable {
    case install
    case update

    /// A version change is an update even when the ping ID is new, so installs that never pinged before do not count as new.
    init?(pingIDIsNew: Bool, updatedFrom: String?) {
        if updatedFrom != nil {
            self = .update
        } else if pingIDIsNew {
            self = .install
        } else {
            return nil
        }
    }

    func body(version: String, previous: String?, pingID: UUID, projectToken: String) throws -> Data {
        let payload = Payload(
            uuid: UUID().uuidString,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            apiKey: projectToken,
            distinctID: pingID.uuidString,
            properties: .init(kind: self, version: version, previous: previous, channel: UpdateChannel(version: version).rawValue)
        )
        return try JSONEncoder().encode(payload)
    }
}

private struct Payload: Encodable {
    struct Properties: Encodable {
        let kind: VersionPing
        let version: String
        let previous: String?
        let channel: String
        let processPersonProfile = false
        let geoIPDisable = true

        enum CodingKeys: String, CodingKey {
            case kind, version, previous, channel
            case processPersonProfile = "$process_person_profile"
            case geoIPDisable = "$geoip_disable"
        }
    }

    let uuid: String
    let timestamp: String
    let apiKey: String
    let event = "version_ping"
    let distinctID: String
    let properties: Properties

    enum CodingKeys: String, CodingKey {
        case apiKey = "api_key"
        case event, uuid, timestamp
        case distinctID = "distinct_id"
        case properties
    }
}

final class VersionPingQueue {
    private static let key = "pendingVersionPings"
    private let defaults: UserDefaults
    private(set) var pending: [Data]

    init(defaults: UserDefaults = .standard) throws {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key) {
            pending = try JSONDecoder().decode([Data].self, from: data)
        } else {
            pending = []
        }
    }

    func enqueue(_ ping: VersionPing, version: String, previous: String?, pingID: UUID, projectToken: String) throws {
        pending.append(try ping.body(version: version, previous: previous, pingID: pingID, projectToken: projectToken))
        try save()
    }

    func acknowledge(_ body: Data) throws {
        pending.removeAll { $0 == body }
        try save()
    }

    func clear() throws {
        pending.removeAll()
        try save()
    }

    private func save() throws {
        defaults.set(try JSONEncoder().encode(pending), forKey: Self.key)
    }
}

@MainActor
enum VersionPinger {
    private static let endpoint = URL(string: "\(Analytics.host)/i/v0/e/")!
    private static let retryInterval: Duration = .seconds(600)

    static func sendPending(launch: LaunchVersion) {
        do {
            let queue = try VersionPingQueue()
            guard SystemContext.isOfficialBuild, UpdateChannel(version: launch.current) != .dev else { return try queue.clear() }
            let pingID = InstallID(key: InstallID.versionPing)
            if let ping = VersionPing(pingIDIsNew: pingID.isNew, updatedFrom: launch.updatedFrom) {
                try queue.enqueue(ping, version: launch.current, previous: launch.updatedFrom, pingID: pingID.value, projectToken: Analytics.projectToken)
            }
            Task {
                do {
                    while true {
                        for body in queue.pending where try await send(body) {
                            try queue.acknowledge(body)
                        }
                        if queue.pending.isEmpty { return }
                        try await Task.sleep(for: retryInterval)
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
