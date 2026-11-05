import Foundation

/// What `voz telemetry` prints. The lists come from the same encoders that send events, so they can't drift.
struct TelemetryReport: Encodable {
    struct Event: Encodable {
        let event: String
        let when: String
        let properties: [String]
    }

    struct Held: Encodable {
        let event: String
        let properties: [String: AnalyticsValue]
    }

    struct Anonymous: Encodable {
        let note = "Always sent, with a new random ID each time and only the UTC day as a timestamp, so events can't be linked to each other or to this Mac."
        let events = TelemetryFact.samples.filter { !$0.isLinked }.map(TelemetryReport.event)
        let otherKey = UsageKeys.other
        let apps = Set(UsageKeys.apps.values).sorted()
    }

    struct Usage: Encodable {
        let enabled: Bool
        let note = "Sent only if you turn on Share usage stats, tied to a random ID. Never text or audio."
        let events = TelemetryFact.samples.filter(\.isLinked).map(TelemetryReport.event) + TelemetryReport.usageEvents
        let otherKey = UsageKeys.other
        let sites = Set(UsageKeys.sites.values).sorted()
    }

    struct Errors: Encodable {
        let enabled: Bool
        let note = "Stack traces and error codes with a new random ID each launch, never text, audio or app names."
    }

    let anonymous = Anonymous()
    let usage: Usage
    let errors: Errors
    let held: [Held]
    let queued: [String]

    init(usageEnabled: Bool, errorsEnabled: Bool, held: [TelemetryFact], queued: [String]) {
        usage = Usage(enabled: usageEnabled)
        errors = Errors(enabled: errorsEnabled)
        self.held = held.map { Held(event: $0.name, properties: $0.properties(in: .current)) }
        self.queued = queued
    }

    var text: String {
        var lines = ["Anonymous: always on", anonymous.note] + anonymous.events.map(Self.line)
        lines += ["  Apps: \(anonymous.apps.joined(separator: ", ")), \(anonymous.otherKey)"]
        lines += ["", "Usage stats: \(usage.enabled ? "on" : "off")", usage.note] + usage.events.map(Self.line)
        lines += ["  Sites: \(usage.sites.joined(separator: ", ")), \(usage.otherKey)"]
        lines += ["", "Crash reports: \(errors.enabled ? "on" : "off")", errors.note]
        if !held.isEmpty { lines += ["", "Held on this Mac until the day ends:"] + held.map(Self.line) }
        if !queued.isEmpty { lines += ["", "Waiting to send: \(queued.joined(separator: ", "))"] }
        return lines.joined(separator: "\n")
    }

    private static func event(_ fact: TelemetryFact) -> Event {
        Event(event: fact.name, when: fact.when, properties: fact.properties(in: .current).keys.sorted())
    }

    /// Variants of one event, such as each error's status, list their fields once
    private static let usageEvents: [Event] = {
        var fieldsByName: [String: Set<String>] = [:]
        for sample in AnalyticsEvent.samples {
            fieldsByName[sample.name, default: Set(SystemContext.properties.keys)].formUnion(sample.properties.keys)
        }
        return fieldsByName.sorted { $0.key < $1.key }.map { Event(event: $0.key, when: "As it happens", properties: $0.value.sorted()) }
    }()

    private static func line(_ event: Event) -> String {
        "  \(event.event): \(event.when). \(event.properties.joined(separator: ", "))"
    }

    private static func line(_ held: Held) -> String {
        let fields = held.properties.sorted { $0.key < $1.key }.map { "\($0.key)=\(describe($0.value))" }
        return "  \(held.event): \(fields.joined(separator: " "))"
    }

    private static func describe(_ value: AnalyticsValue) -> String {
        switch value {
        case let .integer(number): String(number)
        case let .number(number): String(number)
        case let .flag(flag): String(flag)
        case let .text(text): text
        }
    }
}
