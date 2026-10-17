import Combine
import Foundation
import VozCore

enum PermissionFix: Equatable {
    case microphone
    case microphoneBlocked
    case accessibility

    var detail: String {
        switch self {
        case .microphone, .microphoneBlocked: "voz needs the microphone to hear you."
        case .accessibility: "voz needs Accessibility to type into other apps."
        }
    }

    var buttonTitle: String {
        switch self {
        case .microphone: "Allow microphone"
        case .microphoneBlocked: "Open Microphone settings"
        case .accessibility: "Grant Accessibility"
        }
    }
}

enum PopoverStatus: Equatable {
    case ready
    case recording
    case transcribing
    case loadingModel(detail: String, progress: Double?)
    case modelFailed(String)
    case permissionNeeded(PermissionFix)

    var title: String {
        switch self {
        case .ready: "Ready"
        case .recording: "Recording"
        case .transcribing: "Transcribing"
        case .loadingModel: "Model loading"
        case .modelFailed: "Model unavailable"
        case .permissionNeeded: "Permission needed"
        }
    }
}

struct PopoverActions {
    var copy: (TranscriptRecord) -> Void = { _ in }
    var retry: () -> Void = {}
    var openApp: () -> Void = {}
    var openSettings: () -> Void = {}
    var fixPermission: (PermissionFix) -> Void = { _ in }
    var quit: () -> Void = {}
}

@MainActor
final class PopoverModel: ObservableObject {
    private static let copiedDuration = Duration.milliseconds(1400)

    @Published var status = PopoverStatus.ready
    @Published var hint = ""
    @Published var wordsThisWeek = 0
    @Published var transcripts: [TranscriptRecord] = []
    @Published var canRetry = false
    @Published private(set) var copiedID: UUID?

    var actions = PopoverActions()
    private var copiedReset: Task<Void, Never>?

    func copy(_ record: TranscriptRecord) {
        actions.copy(record)
        copiedID = record.id
        copiedReset?.cancel()
        copiedReset = Task {
            try? await Task.sleep(for: Self.copiedDuration)
            guard !Task.isCancelled else { return }
            copiedID = nil
        }
    }
}
