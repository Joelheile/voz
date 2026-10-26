enum AnalyticsEvent: Equatable, Sendable {
    case appOpened
    case appSession(seconds: Int, state: SessionState)
    case modelFailed(model: SpeechModel)
    case appLaunched(byLaunchAgent: Bool)
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
    case setupStepViewed(SetupStage)
    case setupCompleted(allPermissionsGranted: Bool, triedDictation: Bool)
    case extensionChanged(change: ExtensionChange, source: PackageSource)
    case extensionFailed(change: ExtensionChange, source: PackageSource, failure: ExtensionFailure)

    var name: String {
        switch self {
        case .appOpened: "app_opened"
        case .appSession: "app_session"
        case .modelFailed: "model_failed"
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
        case .setupStepViewed: "setup_step_viewed"
        case .setupCompleted: "setup_completed"
        case let .extensionChanged(change, _): change.eventName
        case .extensionFailed: "extension_failed"
        }
    }

    var properties: [String: AnalyticsValue] {
        switch self {
        case let .permissionResult(permission, granted):
            ["permission": .text(permission.rawValue), "granted": .flag(granted)]
        case let .dictationCompleted(metrics):
            Self.properties(of: metrics)
        case let .dictationFailed(stage, errorCode):
            ["stage": .text(stage.rawValue), "error_code": .text(errorCode.rawValue)]
        case let .dictationDiscarded(reason):
            ["reason": .text(reason.rawValue)]
        case let .appSession(seconds, state):
            ["seconds": .integer(seconds), "state": .text(state.rawValue)]
        case let .modelFailed(model):
            ["model": .text(model.rawValue)]
        case let .appLaunched(byLaunchAgent):
            ["by_launch_agent": .flag(byLaunchAgent)]
        case .appOpened, .historyOpened, .statsOpened:
            [:]
        case let .modelDownload(model, seconds, success, bytes):
            ["model": .text(model.rawValue), "seconds": .integer(seconds), "success": .flag(success), "bytes": .integer(bytes)]
        case let .modelLoad(model, coldMs):
            ["model": .text(model.rawValue), "cold_ms": .integer(coldMs)]
        case let .vocabularySuggestion(accepted):
            ["accepted": .flag(accepted)]
        case let .updateInstalled(from, to, channel):
            ["from": .text(from), "to": .text(to), "channel": .text(channel.rawValue)]
        case let .setupStepViewed(step):
            ["step": .text(step.rawValue)]
        case let .setupCompleted(allPermissionsGranted, triedDictation):
            ["all_permissions_granted": .flag(allPermissionsGranted), "tried_dictation": .flag(triedDictation)]
        case let .extensionChanged(_, source):
            Self.properties(of: source)
        case let .extensionFailed(change, source, failure):
            Self.properties(of: source).merging(["change": .text(change.rawValue), "error_code": .text(failure.rawValue)]) { $1 }
        }
    }

    var failure: (stage: String, code: String)? {
        switch self {
        case let .dictationFailed(stage, errorCode): (stage.rawValue, errorCode.rawValue)
        case .modelFailed: ("model_loading", "model_load_failed")
        case .modelDownload(_, _, false, _): ("model_download", "model_download_failed")
        case let .extensionFailed(change, _, failure): ("extension_\(change.rawValue)", failure.rawValue)
        default: nil
        }
    }

    private static func properties(of source: PackageSource) -> [String: AnalyticsValue] {
        switch source {
        case let .npm(name, _): ["source": .text("npm"), "package": .text(name)]
        case .git: ["source": .text("git")]
        case .local: ["source": .text("local")]
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

/// Failures that have no usage event of their own. Codes are fixed strings, never error messages, which can contain paths or text.
enum AppError: String, Sendable {
    case appHang = "app_hang"
    case muteFailed = "mute_failed"
    case segmentTranscriptionFailed = "segment_transcription_failed"
    case speechExtensionFailed = "speech_extension_failed"
    case cleanupFailed = "cleanup_failed"
    case accessibilityDenied = "accessibility_denied"
    case noPasteKey = "no_paste_key"
    case historySaveFailed = "history_save_failed"
    case extensionsStartFailed = "extensions_start_failed"
    case extensionHostCrashLoop = "extension_host_crash_loop"
    case launchAgentFailed = "launch_agent_failed"

    var stage: String {
        switch self {
        case .appHang: "main_thread"
        case .muteFailed: "recording"
        case .segmentTranscriptionFailed, .speechExtensionFailed: "transcription"
        case .cleanupFailed: "cleanup"
        case .accessibilityDenied, .noPasteKey: "delivery"
        case .historySaveFailed: "history"
        case .extensionsStartFailed, .extensionHostCrashLoop: "extensions"
        case .launchAgentFailed: "launch"
        }
    }
}

enum PermissionName: String, Sendable {
    case microphone
    case accessibility
    case inputMonitoring = "input_monitoring"
    case systemAudio = "system_audio"
}

enum DictationStage: String, Sendable {
    case recording
    case transcription
}

enum DictationErrorCode: String, Sendable {
    case microphoneDenied = "microphone_denied"
    case recorderStartFailed = "recorder_start_failed"
    case recorderInterrupted = "recorder_interrupted"
    case transcriptionFailed = "transcription_failed"
}

enum DiscardReason: String, Sendable {
    case tooShort = "too_short"
    case silent
    case emptyTranscript = "empty_transcript"
}

enum DeliveryOutput: String, Sendable {
    case paste
    case clipboard
}

enum SetupStage: String, Sendable {
    case access
    case model
    case tryIt = "try_it"
}

enum ExtensionChange: String, Sendable {
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

enum ExtensionFailure: String, Sendable {
    case bunDownload = "bun_download_failed"
    case packageCommand = "package_command_failed"
}

enum AnalyticsValue: Equatable, Sendable {
    case integer(Int)
    case number(Double)
    case flag(Bool)
    case text(String)
}

struct DictationMetrics: Equatable, Sendable {
    var audioSeconds: Double
    var wordCount: Int
    var sttMs: Int
    var cleanupMs: Int
    var insertMs: Int
    var totalMs: Int
    var model: String
    var selectedModel: String
    var cleanupUsed: Bool
    var cleanupTimedOut: Bool
    var trigger: DictationTrigger
    var output: DeliveryOutput

    init(
        audioSeconds: Double,
        wordCount: Int,
        sttMs: Int,
        cleanupMs: Int,
        insertMs: Int,
        totalMs: Int,
        model: String,
        selectedModel: String,
        cleanupUsed: Bool,
        cleanupTimedOut: Bool,
        trigger: DictationTrigger,
        output: DeliveryOutput
    ) {
        self.audioSeconds = audioSeconds
        self.wordCount = wordCount
        self.sttMs = sttMs
        self.cleanupMs = cleanupMs
        self.insertMs = insertMs
        self.totalMs = totalMs
        self.model = model
        self.selectedModel = selectedModel
        self.cleanupUsed = cleanupUsed
        self.cleanupTimedOut = cleanupTimedOut
        self.trigger = trigger
        self.output = output
    }
}

struct UsageSession {
    private var lastCheckpoint: Int

    init(startedAt: Int) {
        lastCheckpoint = startedAt
    }

    mutating func checkpoint(at seconds: Int) -> Int {
        let elapsed = max(0, seconds - lastCheckpoint)
        lastCheckpoint = seconds
        return elapsed
    }
}

enum SessionState: String, Sendable {
    case started
    case heartbeat
    case ended
}
