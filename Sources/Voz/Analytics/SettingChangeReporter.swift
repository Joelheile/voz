import Combine
import VozCore

@MainActor
final class SettingChangeReporter {
    private var subscriptions: Set<AnyCancellable> = []

    init(settings: AppSettings, analytics: Analytics) {
        let report: (SettingChange) -> Void = { analytics.capture(.settingChanged($0)) }
        observe(settings.$holdToTalk, SettingChange.holdToTalk, report)
        observe(settings.$muteWhileRecording, SettingChange.muteWhileRecording, report)
        observe(settings.$copyToClipboard, SettingChange.copyToClipboard, report)
        observe(settings.$insertIntoApp, SettingChange.insertIntoApp, report)
        observe(settings.$soundCues, SettingChange.soundCues, report)
        observe(settings.$launchAtLogin, SettingChange.launchAtLogin, report)
        observe(settings.$cleanupEnabled, SettingChange.cleanupEnabled, report)
        observe(settings.$analyticsEnabled, SettingChange.analyticsEnabled) {
            if case let .analyticsEnabled(enabled) = $0 { analytics.setEnabled(enabled) }
            report($0)
        }
        observe(settings.$speechModel, SettingChange.speechModel, report)
        observe(settings.$indicatorStyle, SettingChange.indicatorStyle, report)
        observe(settings.$hotkey, SettingChange.hotkey, report)
    }

    private func observe<Value>(
        _ publisher: Published<Value>.Publisher,
        _ change: @escaping (Value) -> SettingChange,
        _ report: @escaping (SettingChange) -> Void
    ) {
        publisher
            .dropFirst()
            .sink { report(change($0)) }
            .store(in: &subscriptions)
    }
}
