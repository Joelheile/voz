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

    /// Each ping gets a fresh ID, so install and update pings cannot be linked to each other or to one Mac.
    func body(version: String, previous: String?, projectToken: String) throws -> Data {
        let properties = Properties(kind: self, version: version, previous: previous, channel: UpdateChannel(version: version).rawValue)
        return try PingPayload(event: "version_ping", distinctID: UUID(), properties: properties, projectToken: projectToken).encoded()
    }

    private struct Properties: Encodable {
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
}

/// Sent without opt-in on the first finished dictation of each UTC day, so active installs can be counted. It carries no text, app names or settings.
enum DailyActivePing {
    private static let lastDayKey = "lastDailyActivePingDay"

    static func claimDay(now: Date, defaults: UserDefaults) -> Bool {
        let day = now.ISO8601Format(.iso8601.year().month().day())
        guard defaults.string(forKey: lastDayKey) != day else { return false }
        defaults.set(day, forKey: lastDayKey)
        return true
    }

    static func body(version: String, model: String, installID: UUID, projectToken: String) throws -> Data {
        let properties = Properties(
            version: version,
            channel: UpdateChannel(version: version).rawValue,
            model: model,
            osMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
            chip: SystemContext.chip
        )
        return try PingPayload(event: "daily_active", distinctID: installID, properties: properties, projectToken: projectToken).encoded()
    }

    private struct Properties: Encodable {
        let version: String
        let channel: String
        let model: String
        let osMajor: Int
        let chip: String
        let processPersonProfile = false
        let geoIPDisable = true

        enum CodingKeys: String, CodingKey {
            case version, channel, model, chip
            case osMajor = "os_major"
            case processPersonProfile = "$process_person_profile"
            case geoIPDisable = "$geoip_disable"
        }
    }
}

private struct PingPayload<Properties: Encodable>: Encodable {
    let uuid = UUID().uuidString
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let apiKey: String
    let event: String
    let distinctID: String
    let properties: Properties

    init(event: String, distinctID: UUID, properties: Properties, projectToken: String) {
        self.event = event
        self.distinctID = distinctID.uuidString
        self.properties = properties
        apiKey = projectToken
    }

    func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

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

    func enqueue(_ body: Data) throws {
        pending.append(body)
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
    private static var queue: VersionPingQueue?
    private static var draining: Task<Void, Never>?

    static func sendPending(launch: LaunchVersion) {
        do {
            let queue = try VersionPingQueue()
            guard sendsPings(version: launch.current) else { return try queue.clear() }
            self.queue = queue
            let pingID = InstallID(key: InstallID.versionPing)
            if let ping = VersionPing(pingIDIsNew: pingID.isNew, updatedFrom: launch.updatedFrom) {
                try queue.enqueue(ping.body(version: launch.current, previous: launch.updatedFrom, projectToken: Analytics.projectToken))
            }
            drain()
        } catch {
            Log.app.error("Version ping queue failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func recordActiveDay(model: String) {
        guard let queue, DailyActivePing.claimDay(now: Date(), defaults: .standard) else { return }
        do {
            let installID = InstallID(key: InstallID.versionPing).value
            try queue.enqueue(DailyActivePing.body(version: SystemContext.appVersion, model: model, installID: installID, projectToken: Analytics.projectToken))
            drain()
        } catch {
            Log.app.error("Daily active ping failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func sendsPings(version: String) -> Bool {
        SystemContext.isOfficialBuild && UpdateChannel(version: version) != .dev
    }

    private static func drain() {
        guard draining == nil, let queue else { return }
        draining = Task {
            defer { draining = nil }
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
