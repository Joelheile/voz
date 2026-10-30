import Foundation
import PostHog
import Synchronization

@MainActor
final class Analytics {
    nonisolated static let projectToken = "phc_pprHknWQHntzTK6vR4vzHK9B6hWNv4nKXbAYpkYcoLXS"
    nonisolated static let host = "https://eu.i.posthog.com"
    private nonisolated static let sharesUsage = Atomic<Bool>(false)
    private nonisolated static let reportsErrors = Atomic<Bool>(false)

    private let installID: UUID
    private let watchdog = HangWatchdog(seconds: 5) {
        Analytics.report(.appHang)
        PostHogSDK.shared.flush()
    }
    private var isSetUp = false

    var isEnabled: Bool { Self.sharesUsage.load(ordering: .relaxed) || Self.reportsErrors.load(ordering: .relaxed) }

    init(usage: Bool, errors: Bool, installID: UUID) {
        self.installID = installID
        setConsent(usage: usage, errors: errors)
    }

    /// Usage events need the usage opt-in. Crash and error reports have their own setting, so a fork with another bundle ID sends neither.
    func setConsent(usage: Bool, errors: Bool) {
        let usage = usage && SystemContext.isOfficialBuild
        let errors = errors && SystemContext.isOfficialBuild
        Self.sharesUsage.store(usage, ordering: .relaxed)
        let errorsChanged = Self.reportsErrors.exchange(errors, ordering: .relaxed) != errors
        if usage || errors {
            setUpIfNeeded()
            PostHogSDK.shared.optIn()
        } else if isSetUp {
            PostHogSDK.shared.optOut()
        }
        if errorsChanged { errors ? watchdog.start() : watchdog.stop() }
    }

    func capture(_ event: AnalyticsEvent) {
        if Self.sharesUsage.load(ordering: .relaxed) {
            var properties = event.properties.mapValues(Self.plainValue)
            properties.merge(SystemContext.properties) { eventValue, _ in eventValue }
            PostHogSDK.shared.capture(event.name, properties: properties)
        }
        if let failure = event.failure { Self.report(stage: failure.stage, code: failure.code) }
    }

    nonisolated static func report(_ error: AppError) {
        report(stage: error.stage, code: error.rawValue)
    }

    private nonisolated static func report(stage: String, code: String) {
        guard reportsErrors.load(ordering: .relaxed) else { return }
        PostHogSDK.shared.capture("$exception", properties: [
            "$exception_list": [["type": "VozError", "value": code, "mechanism": ["type": "handled", "handled": true]]],
            "$exception_fingerprint": "voz.\(stage).\(code)",
            "stage": stage,
            "error_code": code,
            "app_version": SystemContext.appVersion,
            "$process_person_profile": false,
            "$geoip_disable": true,
        ])
    }

    /// The SDK also sends crash reports it captured itself, so consent is checked once more right before anything leaves.
    private nonisolated static func allowed(_ event: PostHogEvent) -> PostHogEvent? {
        let consented = allows(event.event, usage: sharesUsage.load(ordering: .relaxed), errors: reportsErrors.load(ordering: .relaxed))
        guard consented else { return nil }
        event.properties = stampingAppVersion(event.properties)
        return event
    }

    /// Crash reports only carry the SDK's `$app_version`, recorded when the app crashed, so dashboards can filter every event on `app_version`.
    nonisolated static func stampingAppVersion(_ properties: [String: Any]) -> [String: Any] {
        var properties = properties
        if properties["app_version"] == nil {
            properties["app_version"] = properties["$app_version"] ?? SystemContext.appVersion
        }
        return properties
    }

    nonisolated static func allows(_ eventName: String, usage: Bool, errors: Bool) -> Bool {
        eventName == "$exception" ? errors : usage
    }

    func flush() {
        guard isEnabled else { return }
        PostHogSDK.shared.flush()
    }

    private func setUpIfNeeded() {
        guard !isSetUp else { return }
        let installID = installID
        let config = PostHogConfig(projectToken: Self.projectToken, host: Self.host)
        config.captureApplicationLifecycleEvents = false
        config.captureScreenViews = false
        config.errorTrackingConfig.autoCapture = true
        config.errorTrackingConfig.exceptionSteps.enabled = false
        config.preloadFeatureFlags = false
        config.sendFeatureFlagEvent = false
        config.enableSwizzling = false
        config.setDefaultPersonProperties = false
        config.disableGeoIp = true
        config.personProfiles = .identifiedOnly
        config.getAnonymousId = { _ in installID }
        config.setBeforeSend(Self.allowed)
        PostHogSDK.shared.setup(config)
        isSetUp = true
    }

    private nonisolated static func plainValue(_ value: AnalyticsValue) -> Any {
        switch value {
        case let .integer(number): number
        case let .number(number): number
        case let .flag(flag): flag
        case let .text(text): text
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
    static let isOfficialBuild = Bundle.main.bundleIdentifier == bundleID
    static let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"

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
