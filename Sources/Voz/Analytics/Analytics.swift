import Foundation
import PostHog
import VozCore

@MainActor
final class Analytics {
    nonisolated static let projectToken = "phc_pprHknWQHntzTK6vR4vzHK9B6hWNv4nKXbAYpkYcoLXS"
    nonisolated static let host = "https://eu.i.posthog.com"

    private let installID: UUID
    private let context = SystemContext.properties
    private var sessionStarted: SuspendingClock.Instant?
    private var session: UsageSession?
    private var heartbeat: Timer?
    private var isEnabled = false
    private var isSetUp = false

    init(enabled: Bool, installID: UUID) {
        self.installID = installID
        setEnabled(enabled)
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled {
            setUpIfNeeded()
            PostHogSDK.shared.optIn()
            sessionStarted = .now
            session = UsageSession(startedAt: 0)
            capture(.appSession(seconds: 0, state: .started))
            heartbeat = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.checkpoint(.heartbeat) }
            }
        } else if isSetUp {
            heartbeat?.invalidate()
            heartbeat = nil
            session = nil
            sessionStarted = nil
            PostHogSDK.shared.optOut()
        }
    }

    func capture(_ event: AnalyticsEvent) {
        guard isEnabled else { return }
        var properties = event.properties.mapValues(Self.plainValue)
        properties.merge(context) { eventValue, _ in eventValue }
        PostHogSDK.shared.capture(event.name, properties: properties)
        if let failure = event.failure {
            PostHogSDK.shared.capture("$exception", properties: [
                "$exception_list": [["type": "VozError", "value": failure.code, "mechanism": ["type": "handled", "handled": true]]],
                "$exception_fingerprint": "voz.\(failure.stage).\(failure.code)",
                "stage": failure.stage,
                "error_code": failure.code,
                "app_version": SystemContext.appVersion,
                "$process_person_profile": false,
                "$geoip_disable": true,
            ])
        }
    }

    func finishSession() {
        checkpoint(.ended)
        heartbeat?.invalidate()
        heartbeat = nil
    }

    private func checkpoint(_ state: SessionState) {
        guard isEnabled, let sessionStarted, var session else { return }
        let seconds = Int((SuspendingClock.now - sessionStarted).components.seconds)
        let elapsed = session.checkpoint(at: seconds)
        self.session = state == .ended ? nil : session
        capture(.appSession(seconds: elapsed, state: state))
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
        config.errorTrackingConfig.autoCapture = false
        config.errorTrackingConfig.exceptionSteps.enabled = false
        config.preloadFeatureFlags = false
        config.sendFeatureFlagEvent = false
        config.enableSwizzling = false
        config.setDefaultPersonProperties = false
        config.disableGeoIp = true
        config.personProfiles = .identifiedOnly
        config.getAnonymousId = { _ in installID }
        PostHogSDK.shared.setup(config)
        isSetUp = true
    }

    private static func plainValue(_ value: AnalyticsValue) -> Any {
        switch value {
        case let .integer(number): number
        case let .number(number): number
        case let .flag(flag): flag
        case let .text(text): text
        }
    }
}
