import Testing
@testable import VozCore

@Suite struct AnalyticsEventTests {
    private static let metrics = DictationMetrics(
        audioSeconds: 4.26, wordCount: 12, sttMs: 80, cleanupMs: 200, insertMs: 60, totalMs: 400,
        model: .parakeetUltra, selectedModel: .parakeetUltra, cleanupUsed: true, cleanupTimedOut: false,
        trigger: .hold, output: .paste
    )

    private static let settingKeys: Set<String> = [
        "hold_to_talk", "mute_while_recording", "copy_to_clipboard", "insert_into_app", "sound_cues",
        "launch_at_login", "cleanup_enabled", "analytics_enabled", "speech_model", "indicator_style", "hotkey",
    ]

    private static let changes: [SettingChange] = [
        .holdToTalk(true), .muteWhileRecording(false), .copyToClipboard(true), .insertIntoApp(true),
        .soundCues(false), .launchAtLogin(true), .cleanupEnabled(false), .analyticsEnabled(true),
        .speechModel(.parakeetV2), .indicatorStyle(.pill),
        .hotkey(makeCombinationHotkey()), .hotkey(.rightCommand),
    ]

    private static var events: [AnalyticsEvent] {
        [
            .appInstalled(launchMs: 300), .appLaunched(launchMs: 300),
            .permissionResult(permission: .inputMonitoring, granted: true),
            .dictationCompleted(metrics),
            .dictationFailed(stage: .transcription, errorCode: .transcriptionFailed),
            .dictationDiscarded(reason: .silent),
            .retryUsed,
            .modelDownload(model: .parakeetV2, seconds: 30, success: true, bytes: 1_000_000),
            .modelLoad(model: .parakeetUltra, coldMs: 900),
            .vocabularySuggestion(accepted: false),
            .historyOpened, .statsOpened,
            .updateInstalled(from: "0.1.0", to: "0.2.0-beta.3", channel: .beta),
        ] + changes.map { .settingChanged($0) }
    }

    @Test func propertyValuesAreNumbersBooleansOrFixedLabels() {
        for event in Self.events {
            for (name, value) in event.properties {
                guard case let .label(label) = value else { continue }
                let allowed = name == "key" ? Self.settingKeys : AnalyticsLabels.allValues
                #expect(allowed.contains(label), "\(event.name).\(name) = \(label)")
            }
        }
    }

    @Test func settingChangesNeverCarryFreeText() {
        let hotkeyValues = Self.changes.compactMap { change -> String? in
            guard case .hotkey = change, case let .label(label) = change.value else { return nil }
            return label
        }
        #expect(hotkeyValues == ["key_combination", "modifier_key"])
    }

    @Test func eventNamesMatchThePlan() {
        let names = Set(Self.events.map(\.name))
        #expect(names.isSuperset(of: [
            "app_installed", "app_launched", "permission_result",
            "dictation_completed", "dictation_failed", "dictation_discarded", "retry_used",
            "model_download", "model_load", "vocabulary_suggestion", "setting_changed",
            "history_opened", "stats_opened", "update_installed",
        ]))
    }

    @Test func dictationCompletedCarriesExactlyThePlannedProperties() {
        let keys = Set(AnalyticsEvent.dictationCompleted(Self.metrics).properties.keys)
        #expect(keys == [
            "audio_s", "word_count", "stt_ms", "cleanup_ms", "insert_ms", "total_ms",
            "model", "selected_model", "cleanup_used", "cleanup_timed_out", "trigger", "output",
        ])
    }

    @Test func audioSecondsRoundToOneDecimal() {
        #expect(AnalyticsEvent.dictationCompleted(Self.metrics).properties["audio_s"] == .number(4.3))
    }
}
