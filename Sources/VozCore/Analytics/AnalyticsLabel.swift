public enum PermissionName: String, Sendable {
    case microphone
    case accessibility
    case inputMonitoring = "input_monitoring"
    case systemAudio = "system_audio"
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

public enum SetupStage: String, Sendable {
    case access
    case model
    case tryIt = "try_it"
}

public enum ExtensionChange: String, Sendable {
    case install
    case update
    case remove

    var eventName: String {
        switch self {
        case .install: "extension_installed"
        case .update: "extension_updated"
        case .remove: "extension_removed"
        }
    }
}

public enum ExtensionFailure: String, Sendable {
    case bunDownload = "bun_download_failed"
    case packageCommand = "package_command_failed"
}
