import Combine
import Foundation

enum PermissionFix: Equatable {
    case microphone
    case microphoneBlocked
    case accessibility

    var detail: String {
        switch self {
        case .microphone, .microphoneBlocked: "Allow microphone access to dictate."
        case .accessibility: "Allow Accessibility so Voz can type into other apps."
        }
    }

    var buttonTitle: String {
        switch self {
        case .microphone: "Allow microphone"
        case .microphoneBlocked: "Open microphone settings"
        case .accessibility: "Allow Accessibility"
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
        case .loadingModel(_, nil): "Preparing model"
        case .loadingModel: "Downloading model"
        case .modelFailed: "Model unavailable"
        case .permissionNeeded: "Permission needed"
        }
    }
}

enum PopoverPage {
    case home
    case settings
    case dictionary
    case insights
    case extensions
    case cleanupPrompt
    case cleanupSteps
    case speechModel

    var title: String {
        switch self {
        case .home: "Voz"
        case .settings: "Settings"
        case .dictionary: "Dictionary"
        case .insights: "Insights"
        case .extensions: "Extensions"
        case .cleanupPrompt: "Cleanup prompt"
        case .cleanupSteps: "Cleanup steps"
        case .speechModel: "Speech model"
        }
    }

    var parent: PopoverPage {
        [.dictionary, .cleanupPrompt, .cleanupSteps, .speechModel].contains(self) ? .settings : .home
    }
}

struct PopoverActions {
    var copy: (TranscriptRecord) -> Void = { _ in }
    var fixPermission: (PermissionFix) -> Void = { _ in }
    var retryModel: () -> Void = {}
    var checkForUpdates: () -> Void = {}
    var finishSetup: () -> Void = {}
    var resize: (CGSize) -> Void = { _ in }
    var quit: () -> Void = {}
}

@MainActor
final class PopoverModel: ObservableObject {
    private static let copiedDuration = Duration.milliseconds(1400)

    @Published var status = PopoverStatus.ready
    @Published var hint = ""
    @Published var page = PopoverPage.home
    @Published var needsSetup = false
    @Published private(set) var copiedID: UUID?

    var actions = PopoverActions()
    private var copiedReset: Task<Void, Never>?

    func goBack() {
        page = page.parent
    }

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
