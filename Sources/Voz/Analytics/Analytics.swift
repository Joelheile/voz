import Foundation
import PostHog
import VozCore

@MainActor
final class Analytics {
    private static let projectToken = "phc_pprHknWQHntzTK6vR4vzHK9B6hWNv4nKXbAYpkYcoLXS"
    private static let host = "https://eu.i.posthog.com"
    private static let debugVariable = "VOZ_ANALYTICS_DEBUG"

    private let installID: UUID
    private let context = SystemContext.properties
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
        } else if isSetUp {
            PostHogSDK.shared.optOut()
        }
    }

    func capture(_ event: AnalyticsEvent) {
        guard isEnabled else { return }
        var properties = event.properties.mapValues(Self.plainValue)
        properties.merge(context) { eventValue, _ in eventValue }
        PostHogSDK.shared.capture(event.name, properties: properties)
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
        config.preloadFeatureFlags = false
        config.sendFeatureFlagEvent = false
        config.enableSwizzling = false
        config.setDefaultPersonProperties = false
        config.disableGeoIp = true
        config.personProfiles = .identifiedOnly
        config.getAnonymousId = { _ in installID }
        config.debug = ProcessInfo.processInfo.environment[Self.debugVariable] != nil
        PostHogSDK.shared.setup(config)
        isSetUp = true
    }

    private static func plainValue(_ value: AnalyticsValue) -> Any {
        switch value {
        case let .integer(number): number
        case let .number(number): number
        case let .flag(flag): flag
        case let .label(label): label
        case let .version(version): version
        }
    }
}
