import Foundation

/// Counts every event on this Mac, and sends the opt-in events tied to the install ID. Call sites use this and never touch the network.
@MainActor
final class Analytics {
    nonisolated static let projectToken = "phc_pprHknWQHntzTK6vR4vzHK9B6hWNv4nKXbAYpkYcoLXS"
    nonisolated static let host = "https://eu.i.posthog.com"

    private let installID: UUID
    private let crashReports = CrashReports()
    private let sender = TelemetrySender(key: TelemetrySender.usageKey)
    private var sharesUsage = false

    var reportsCrashes: Bool { crashReports.isEnabled }

    init(usage: Bool, errors: Bool, installID: UUID) {
        self.installID = installID
        setConsent(usage: usage, errors: errors)
    }

    /// Opt-in events need Share usage stats. Crash reports have their own setting, and a fork with another bundle ID or a dev build sends neither.
    func setConsent(usage: Bool, errors: Bool) {
        sharesUsage = usage && SystemContext.sendsTelemetry
        // Dev builds share defaults with the installed app, so they leave its queue alone
        if sharesUsage {
            sender.drain()
        } else if SystemContext.sendsTelemetry {
            sender.clear()
        }
        crashReports.setEnabled(errors && SystemContext.sendsTelemetry)
    }

    func capture(_ event: AnalyticsEvent) {
        Self.count(event)
        if sharesUsage { enqueue { try Self.body(for: event, installID: installID, now: Date()) } }
        if let failure = event.failure {
            CrashReports.capture(stage: failure.stage, code: failure.code, details: failure.status.map { ["os_status": $0] } ?? [:])
        }
    }

    /// Opt-in facts such as site totals. Without the opt-in they go nowhere.
    func send(_ facts: [DatedFact]) {
        guard sharesUsage else { return }
        for fact in facts { enqueue { try TelemetryPayload.body(fact, installID: installID, environment: .current) } }
    }

    nonisolated static func report(_ error: AppError, details: [String: Any] = [:]) {
        if SystemContext.sendsTelemetry { TelemetryStore.shared.addFailure(.failure(error), now: Date()) }
        CrashReports.capture(stage: error.stage, code: error.rawValue, details: details)
    }

    func flush() {
        crashReports.flush()
    }

    nonisolated static func body(for event: AnalyticsEvent, installID: UUID, now: Date) throws -> Data {
        let properties = event.properties.merging(SystemContext.properties.mapValues(AnalyticsValue.text)) { eventValue, _ in eventValue }
        return try TelemetryPayload.body(event: event.name, distinctID: installID, timestamp: now.ISO8601Format(), properties: properties)
    }

    private static func count(_ event: AnalyticsEvent) {
        guard SystemContext.sendsTelemetry else { return }
        if let failure = event.countedFailure { TelemetryStore.shared.addFailure(failure, now: Date()) }
        if let milestone = event.milestone { TelemetryStore.shared.reach(milestone, now: Date()) }
    }

    private func enqueue(_ body: () throws -> Data) {
        do {
            sender.send([try body()])
        } catch {
            Log.app.error("Could not encode an event: \(error.localizedDescription, privacy: .public)")
        }
    }
}

struct InstallID {
    static let usage = "installId"
    static let versionPing = "versionPingId"

    let value: UUID
    let isNew: Bool

    init(key: String, defaults: UserDefaults = .standard) {
        if let stored = defaults.string(forKey: key).flatMap(UUID.init) {
            value = stored
            isNew = false
        } else {
            value = UUID()
            isNew = true
            defaults.set(value.uuidString, forKey: key)
        }
    }
}

enum SystemContext {
    static let bundleID = "com.joelheile.voz"
    /// `scripts/make-app.sh --test` builds this one. It keeps its own data, so tests can run beside your installed Voz.
    static let isTestBuild = Bundle.main.bundleIdentifier == "\(bundleID).test"
    static let isOfficialBuild = Bundle.main.bundleIdentifier == bundleID
    static let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    static let sendsTelemetry = isOfficialBuild && UpdateChannel(version: appVersion) != .dev

    static let properties: [String: String] = [
        "app_version": appVersion,
        "os_version": ProcessInfo.processInfo.operatingSystemVersionString,
        "chip": chip,
    ]

    static let chip: String = {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0 else { return "unknown" }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 else { return "unknown" }
        return String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
    }()
}
