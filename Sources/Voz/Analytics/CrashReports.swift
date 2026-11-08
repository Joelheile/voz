import Foundation
import PostHog
import Synchronization

/// Crash and error reports, with a new random ID each launch. This is the only file that uses the PostHog SDK.
@MainActor
final class CrashReports {
    private nonisolated static let enabled = Atomic<Bool>(false)

    private let launchID = UUID()
    private let watchdog = HangWatchdog(seconds: 5) {
        Analytics.report(.appHang, details: ["activity": MainThreadActivity.name ?? "unknown"])
        PostHogSDK.shared.flush()
    }
    private var isSetUp = false

    var isEnabled: Bool { Self.enabled.load(ordering: .relaxed) }

    func setEnabled(_ isEnabled: Bool) {
        let changed = Self.enabled.exchange(isEnabled, ordering: .relaxed) != isEnabled
        if isEnabled {
            setUpIfNeeded()
            PostHogSDK.shared.optIn()
        } else if isSetUp {
            PostHogSDK.shared.optOut()
        }
        if changed { isEnabled ? watchdog.start() : watchdog.stop() }
    }

    func flush() {
        guard isEnabled else { return }
        PostHogSDK.shared.flush()
    }

    nonisolated static func capture(stage: String, code: String, details: [String: Any] = [:]) {
        guard enabled.load(ordering: .relaxed) else { return }
        PostHogSDK.shared.capture("$exception", properties: exception(stage: stage, code: code, details: details))
    }

    /// The code names the issue in PostHog, and the details in the message tell reports of one issue apart
    nonisolated static func exception(stage: String, code: String, details: [String: Any]) -> [String: Any] {
        let message = ([code] + details.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }).joined(separator: " ")
        return details.merging([
            "$exception_list": [["type": code, "value": message, "mechanism": ["type": "handled", "handled": true]]],
            "$exception_fingerprint": "voz.\(stage).\(code)",
            "stage": stage,
            "error_code": code,
            "app_version": SystemContext.appVersion,
            "$process_person_profile": false,
            "$geoip_disable": true,
        ]) { $1 }
    }

    /// The SDK also sends crash reports it captured itself, so this runs once more right before anything leaves
    private nonisolated static func allowed(_ event: PostHogEvent) -> PostHogEvent? {
        guard allows(event.event, errors: enabled.load(ordering: .relaxed)) else { return nil }
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

    nonisolated static func allows(_ eventName: String, errors: Bool) -> Bool {
        eventName == "$exception" && errors
    }

    private func setUpIfNeeded() {
        guard !isSetUp else { return }
        let launchID = launchID
        let config = PostHogConfig(projectToken: Analytics.projectToken, host: Analytics.host)
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
        config.getAnonymousId = { _ in launchID }
        config.setBeforeSend(Self.allowed)
        PostHogSDK.shared.setup(config)
        isSetUp = true
    }
}
