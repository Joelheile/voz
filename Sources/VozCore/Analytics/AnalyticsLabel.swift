public protocol AnalyticsLabel: RawRepresentable, CaseIterable, Sendable where RawValue == String {}

extension SpeechModel: AnalyticsLabel {}
extension IndicatorStyle: AnalyticsLabel {}

public enum PermissionName: String, AnalyticsLabel {
    case microphone
    case accessibility
    case inputMonitoring = "input_monitoring"
}

public enum DictationStage: String, AnalyticsLabel {
    case recording
    case transcription
}

public enum DictationErrorCode: String, AnalyticsLabel {
    case microphoneDenied = "microphone_denied"
    case recorderStartFailed = "recorder_start_failed"
    case transcriptionFailed = "transcription_failed"
}

public enum DiscardReason: String, AnalyticsLabel {
    case tooShort = "too_short"
    case silent
    case emptyTranscript = "empty_transcript"
}

public enum DictationTrigger: String, AnalyticsLabel {
    case tap
    case hold
}

public enum DeliveryOutput: String, AnalyticsLabel {
    case paste
    case clipboard
}

public enum HotkeyKind: String, AnalyticsLabel {
    case modifierKey = "modifier_key"
    case keyCombination = "key_combination"
}

public enum AnalyticsLabels {
    public static let allValues: Set<String> = {
        var values: [String] = []
        values += rawValues(IndicatorStyle.self)
        values += rawValues(PermissionName.self)
        values += rawValues(DictationStage.self)
        values += rawValues(DictationErrorCode.self)
        values += rawValues(DiscardReason.self)
        values += rawValues(DictationTrigger.self)
        values += rawValues(DeliveryOutput.self)
        values += rawValues(SpeechModel.self)
        values += rawValues(HotkeyKind.self)
        values += rawValues(UpdateChannel.self)
        return Set(values)
    }()

    private static func rawValues<Label: AnalyticsLabel>(_ type: Label.Type) -> [String] {
        type.allCases.map(\.rawValue)
    }
}
