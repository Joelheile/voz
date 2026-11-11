import AVFoundation
import Combine
import Foundation

enum SetupStep: Int, CaseIterable {
    case access
    case languages
    case model
    case extras
    case tryIt

    var stage: SetupStage {
        switch self {
        case .access: .access
        case .languages: .languages
        case .model: .model
        case .extras: .extras
        case .tryIt: .tryIt
        }
    }
}

@MainActor
final class SetupModel: ObservableObject {
    @Published var step = SetupStep.access {
        didSet { stepChanged() }
    }
    @Published var triedDictation = false
    @Published private(set) var microphoneStatus = Permissions.microphoneStatus
    @Published private(set) var accessibilityGranted = Permissions.accessibilityGranted
    @Published private(set) var inputMonitoringGranted = Permissions.inputMonitoringGranted
    @Published private(set) var systemAudioGranted = Permissions.systemAudioGranted

    private let analytics: Analytics
    private let prepareModel: () -> Void
    private var modelPrepared = false

    init(analytics: Analytics, prepareModel: @escaping () -> Void) {
        self.analytics = analytics
        self.prepareModel = prepareModel
    }

    var microphoneGranted: Bool { microphoneStatus == .authorized }
    var allGranted: Bool { microphoneGranted && accessibilityGranted && inputMonitoringGranted }

    func refreshPermissions() {
        Task { apply(await PermissionSnapshot.read()) }
    }

    func apply(_ access: PermissionSnapshot) {
        if microphoneStatus != access.microphone { microphoneStatus = access.microphone }
        if accessibilityGranted != access.accessibility { accessibilityGranted = access.accessibility }
        if inputMonitoringGranted != access.inputMonitoring { inputMonitoringGranted = access.inputMonitoring }
        if systemAudioGranted != access.systemAudio { systemAudioGranted = access.systemAudio }
    }

    func requestMicrophone() {
        Task {
            await microphoneStatus == .notDetermined ? Permissions.requestMicrophone() : Permissions.requestBlockedMicrophone()
            refreshPermissions()
        }
    }

    func requestAccessibility() {
        Permissions.requestAccessibility()
    }

    func requestInputMonitoring() {
        Permissions.requestInputMonitoring()
    }

    func requestSystemAudio() {
        Task {
            await Permissions.requestSystemAudio()
            refreshPermissions()
        }
    }

    func reportCompletion() {
        refreshPermissions()
        analytics.capture(.permissionResult(permission: .microphone, granted: microphoneGranted))
        analytics.capture(.permissionResult(permission: .accessibility, granted: accessibilityGranted))
        analytics.capture(.permissionResult(permission: .inputMonitoring, granted: inputMonitoringGranted))
        analytics.capture(.permissionResult(permission: .systemAudio, granted: systemAudioGranted))
        analytics.capture(.setupCompleted(allPermissionsGranted: allGranted, triedDictation: triedDictation))
    }

    private func stepChanged() {
        analytics.capture(.setupStepViewed(step.stage))
        guard step == .model, !modelPrepared else { return }
        modelPrepared = true
        prepareModel()
    }
}
