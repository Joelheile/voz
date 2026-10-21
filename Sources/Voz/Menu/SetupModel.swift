import AVFoundation
import Combine
import Foundation
import VozCore

enum SetupStep: Int, CaseIterable {
    case access
    case model
    case tryIt

    var stage: SetupStage {
        switch self {
        case .access: .access
        case .model: .model
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
        microphoneStatus = Permissions.microphoneStatus
        accessibilityGranted = Permissions.accessibilityGranted
        inputMonitoringGranted = Permissions.inputMonitoringGranted
    }

    func requestMicrophone() {
        if microphoneStatus == .notDetermined {
            Task {
                await Permissions.requestMicrophone()
                refreshPermissions()
            }
        } else {
            Permissions.openSettings(.microphone)
        }
    }

    func requestAccessibility() {
        Permissions.promptForAccessibility()
    }

    func requestInputMonitoring() {
        Permissions.requestInputMonitoring()
        Permissions.openSettings(.inputMonitoring)
    }

    func reportCompletion() {
        refreshPermissions()
        analytics.capture(.permissionResult(permission: .microphone, granted: microphoneGranted))
        analytics.capture(.permissionResult(permission: .accessibility, granted: accessibilityGranted))
        analytics.capture(.permissionResult(permission: .inputMonitoring, granted: inputMonitoringGranted))
        analytics.capture(.setupCompleted(allPermissionsGranted: allGranted, triedDictation: triedDictation))
    }

    private func stepChanged() {
        analytics.capture(.setupStepViewed(step.stage))
        guard step == .model, !modelPrepared else { return }
        modelPrepared = true
        prepareModel()
    }
}
