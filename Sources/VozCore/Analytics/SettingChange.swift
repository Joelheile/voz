public enum SettingChange: Equatable, Sendable {
    case holdToTalk(Bool)
    case muteWhileRecording(Bool)
    case copyToClipboard(Bool)
    case insertIntoApp(Bool)
    case soundCues(Bool)
    case launchAtLogin(Bool)
    case cleanupEnabled(Bool)
    case analyticsEnabled(Bool)
    case speechModel(SpeechModel)
    case indicatorStyle(IndicatorStyle)
    case hotkey(Hotkey)

    var key: String {
        switch self {
        case .holdToTalk: "hold_to_talk"
        case .muteWhileRecording: "mute_while_recording"
        case .copyToClipboard: "copy_to_clipboard"
        case .insertIntoApp: "insert_into_app"
        case .soundCues: "sound_cues"
        case .launchAtLogin: "launch_at_login"
        case .cleanupEnabled: "cleanup_enabled"
        case .analyticsEnabled: "analytics_enabled"
        case .speechModel: "speech_model"
        case .indicatorStyle: "indicator_style"
        case .hotkey: "hotkey"
        }
    }

    var value: AnalyticsValue {
        switch self {
        case let .holdToTalk(flag), let .muteWhileRecording(flag), let .copyToClipboard(flag),
             let .insertIntoApp(flag), let .soundCues(flag), let .launchAtLogin(flag),
             let .cleanupEnabled(flag), let .analyticsEnabled(flag):
            .flag(flag)
        case let .speechModel(model): .label(model.rawValue)
        case let .indicatorStyle(style): .label(style.rawValue)
        case let .hotkey(hotkey): .label(hotkey.kind.rawValue)
        }
    }
}

extension Hotkey {
    var kind: HotkeyKind {
        isModifierOnly ? .modifierKey : .keyCombination
    }
}
