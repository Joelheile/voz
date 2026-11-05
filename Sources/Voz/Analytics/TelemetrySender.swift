import Foundation

struct CapturePayload<Properties: Encodable>: Encodable {
    let uuid = UUID().uuidString
    let timestamp: String
    let apiKey: String
    let event: String
    let distinctID: String
    let properties: Properties

    init(event: String, distinctID: UUID, timestamp: String = ISO8601DateFormatter().string(from: Date()), properties: Properties, projectToken: String) {
        self.event = event
        self.distinctID = distinctID.uuidString
        self.timestamp = timestamp
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

enum TelemetryPayload {
    static func body(event: String, distinctID: UUID, timestamp: String, properties: [String: AnalyticsValue]) throws -> Data {
        let controls: [String: AnalyticsValue] = ["$process_person_profile": .flag(false), "$geoip_disable": .flag(true)]
        return try CapturePayload(
            event: event, distinctID: distinctID, timestamp: timestamp, properties: properties.merging(controls) { $1 }, projectToken: Analytics.projectToken
        ).encoded()
    }

    /// A fact gets a new random ID unless it's an opt-in fact, and its only time is the start of its UTC day
    static func body(_ dated: DatedFact, installID: UUID, environment: TelemetryEnvironment) throws -> Data {
        try body(
            event: dated.fact.name,
            distinctID: dated.fact.isLinked ? installID : UUID(),
            timestamp: "\(dated.day)T00:00:00Z",
            properties: dated.fact.properties(in: environment)
        )
    }
}

/// The only network path for usage data: a queue saved to disk, so a quit or a lost connection doesn't lose events
@MainActor
final class TelemetrySender {
    nonisolated static let anonymousKey = "pendingVersionPings"
    nonisolated static let usageKey = "pendingUsageEvents"
    /// Anonymous events go out one by one, so the time PostHog receives them can't tie a day's facts together
    nonisolated static let anonymousSpacingSeconds = 30...120
    private nonisolated static let endpoint = URL(string: "\(Analytics.host)/i/v0/e/")!
    private static let retryInterval: Duration = .seconds(600)
    private static let maxQueued = 500

    private let key: String
    private let spacingSeconds: ClosedRange<Int>?
    private let defaults: UserDefaults
    private let post: @Sendable (Data) async -> Bool
    private let sleep: @Sendable (Duration) async throws -> Void
    private(set) var pending: [Data]
    private var draining: Task<Void, Never>?

    init(
        key: String,
        spacingSeconds: ClosedRange<Int>? = nil,
        defaults: UserDefaults = .standard,
        post: @escaping @Sendable (Data) async -> Bool = TelemetrySender.post,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.key = key
        self.spacingSeconds = spacingSeconds
        self.defaults = defaults
        self.post = post
        self.sleep = sleep
        pending = Self.saved(key: key, defaults: defaults)
    }

    func send(_ bodies: [Data]) {
        guard !bodies.isEmpty else { return }
        pending = Array((pending + bodies.shuffled()).suffix(Self.maxQueued))
        save()
        drain()
    }

    func drain() {
        guard draining == nil, !pending.isEmpty else { return }
        draining = Task { [weak self] in
            await self?.sendAll()
            self?.draining = nil
        }
    }

    func clear() {
        pending = []
        save()
    }

    func finishSending() async {
        await draining?.value
    }

    /// The event names waiting to go, for `voz telemetry`
    nonisolated static func queuedEvents(in defaults: UserDefaults) -> [String] {
        ([anonymousKey, usageKey].flatMap { saved(key: $0, defaults: defaults) }).compactMap { body in
            (try? JSONDecoder().decode(QueuedEvent.self, from: body))?.event
        }
    }

    private struct QueuedEvent: Decodable {
        let event: String
    }

    private func sendAll() async {
        do {
            while let body = pending.first {
                if let spacingSeconds { try await sleep(.seconds(Int.random(in: spacingSeconds))) }
                guard pending.first == body else { continue }
                let wasSent = await post(body)
                // A clear during the send wins, so an opted-out event doesn't come back
                guard let index = pending.firstIndex(of: body) else { continue }
                pending.remove(at: index)
                if wasSent {
                    save()
                    continue
                }
                // A rejected event goes to the back, so it can't hold up the rest
                pending.append(body)
                save()
                try await sleep(Self.retryInterval)
            }
        } catch {
            Log.app.error("Telemetry queue stopped: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func save() {
        do {
            defaults.set(try JSONEncoder().encode(pending), forKey: key)
        } catch {
            Log.app.error("Could not save the telemetry queue: \(error.localizedDescription, privacy: .public)")
        }
    }

    private nonisolated static func saved(key: String, defaults: UserDefaults) -> [Data] {
        guard let data = defaults.data(forKey: key) else { return [] }
        do {
            return try JSONDecoder().decode([Data].self, from: data)
        } catch {
            Log.app.error("Could not read the telemetry queue: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private nonisolated static func post(_ body: Data) async -> Bool {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(status) { return true }
            Log.app.error("Telemetry returned status \(status), kept for retry")
        } catch {
            Log.app.error("Telemetry failed, kept for retry: \(error.localizedDescription, privacy: .public)")
        }
        return false
    }
}
