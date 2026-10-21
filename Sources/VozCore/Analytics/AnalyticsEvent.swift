public enum AnalyticsEvent: Equatable, Sendable {
    case appInstalled
    case appLaunched
    case permissionResult(permission: PermissionName, granted: Bool)
    case dictationCompleted(DictationMetrics)
    case dictationFailed(stage: DictationStage, errorCode: DictationErrorCode)
    case dictationDiscarded(reason: DiscardReason)
    case modelDownload(model: SpeechModel, seconds: Int, success: Bool, bytes: Int)
    case modelLoad(model: SpeechModel, coldMs: Int)
    case vocabularySuggestion(accepted: Bool)
    case historyOpened
    case statsOpened
    case updateInstalled(from: String, to: String, channel: UpdateChannel)

    public var name: String {
        switch self {
        case .appInstalled: "app_installed"
        case .appLaunched: "app_launched"
        case .permissionResult: "permission_result"
        case .dictationCompleted: "dictation_completed"
        case .dictationFailed: "dictation_failed"
        case .dictationDiscarded: "dictation_discarded"
        case .modelDownload: "model_download"
        case .modelLoad: "model_load"
        case .vocabularySuggestion: "vocabulary_suggestion"
        case .historyOpened: "history_opened"
        case .statsOpened: "stats_opened"
        case .updateInstalled: "update_installed"
        }
    }

    public var properties: [String: AnalyticsValue] {
        switch self {
        case let .permissionResult(permission, granted):
            ["permission": .text(permission.rawValue), "granted": .flag(granted)]
        case let .dictationCompleted(metrics):
            Self.properties(of: metrics)
        case let .dictationFailed(stage, errorCode):
            ["stage": .text(stage.rawValue), "error_code": .text(errorCode.rawValue)]
        case let .dictationDiscarded(reason):
            ["reason": .text(reason.rawValue)]
        case .appInstalled, .appLaunched, .historyOpened, .statsOpened:
            [:]
        case let .modelDownload(model, seconds, success, bytes):
            ["model": .text(model.rawValue), "seconds": .integer(seconds), "success": .flag(success), "bytes": .integer(bytes)]
        case let .modelLoad(model, coldMs):
            ["model": .text(model.rawValue), "cold_ms": .integer(coldMs)]
        case let .vocabularySuggestion(accepted):
            ["accepted": .flag(accepted)]
        case let .updateInstalled(from, to, channel):
            ["from": .text(from), "to": .text(to), "channel": .text(channel.rawValue)]
        }
    }

    private static func properties(of metrics: DictationMetrics) -> [String: AnalyticsValue] {
        [
            "audio_s": .number((metrics.audioSeconds * 10).rounded() / 10),
            "word_count": .integer(metrics.wordCount),
            "stt_ms": .integer(metrics.sttMs),
            "cleanup_ms": .integer(metrics.cleanupMs),
            "insert_ms": .integer(metrics.insertMs),
            "total_ms": .integer(metrics.totalMs),
            "model": .text(metrics.model),
            "selected_model": .text(metrics.selectedModel),
            "cleanup_used": .flag(metrics.cleanupUsed),
            "cleanup_timed_out": .flag(metrics.cleanupTimedOut),
            "trigger": .text(metrics.trigger.rawValue),
            "output": .text(metrics.output.rawValue),
        ]
    }
}
