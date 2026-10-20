public enum PermissionName: String, Sendable {
    case microphone
    case accessibility
    case inputMonitoring = "input_monitoring"
}

public enum DictationStage: String, Sendable {
    case recording
    case transcription
}

public enum DictationErrorCode: String, Sendable {
    case microphoneDenied = "microphone_denied"
    case recorderStartFailed = "recorder_start_failed"
    case transcriptionFailed = "transcription_failed"
}

public enum DiscardReason: String, Sendable {
    case tooShort = "too_short"
    case silent
    case emptyTranscript = "empty_transcript"
}

public enum DictationTrigger: String, Sendable {
    case tap
    case hold
}

public enum DeliveryOutput: String, Sendable {
    case paste
    case clipboard
}
