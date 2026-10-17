public enum DictationPhase: Sendable {
    case idle
    case recording
    case transcribing
}

public enum DictationCommand: Equatable, Sendable {
    case start(DictationTrigger)
    case stop
    case rejectBusy
    case ignore

    public static func command(for action: HotkeyAction, in phase: DictationPhase) -> DictationCommand {
        switch (action, phase) {
        case (.toggle, .idle): .start(.tap)
        case (.start, .idle): .start(.hold)
        case (.toggle, .recording), (.stop, .recording): .stop
        case (.toggle, .transcribing), (.start, .transcribing): .rejectBusy
        default: .ignore
        }
    }
}
