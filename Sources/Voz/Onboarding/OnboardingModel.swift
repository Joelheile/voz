import AVFoundation
import Combine
import Foundation
import VozCore

@MainActor
final class OnboardingModel: ObservableObject {
    @Published private(set) var step = OnboardingStep.microphone
    @Published private(set) var microphoneStatus = Permissions.microphoneStatus
    @Published private(set) var accessibilityGranted = Permissions.accessibilityGranted
    @Published private(set) var inputMonitoringGranted = Permissions.inputMonitoringGranted
    @Published var testText = ""

    private let analytics: Analytics
    private let onLanguageChosen: () -> Void
    private let onFinish: () -> Void
    private var stepStarted = Date()

    init(analytics: Analytics, onLanguageChosen: @escaping () -> Void, onFinish: @escaping () -> Void) {
        self.analytics = analytics
        self.onLanguageChosen = onLanguageChosen
        self.onFinish = onFinish
    }

    var isLastStep: Bool { step == OnboardingStep.allCases.last }

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
            Permissions.openSettings(pane: "Privacy_Microphone")
        }
    }

    func requestAccessibility() {
        Permissions.promptForAccessibility()
    }

    func requestInputMonitoring() {
        Permissions.requestInputMonitoring()
        Permissions.openSettings(pane: "Privacy_ListenEvent")
    }

    func next() {
        reportCompletedStep()
        if step == .language { onLanguageChosen() }
        let steps = OnboardingStep.allCases
        if let index = steps.firstIndex(of: step), steps.indices.contains(index + 1) {
            step = steps[index + 1]
            stepStarted = Date()
        } else {
            onFinish()
        }
    }

    private func reportCompletedStep() {
        refreshPermissions()
        switch step {
        case .microphone: analytics.capture(.permissionResult(permission: .microphone, granted: microphoneStatus == .authorized))
        case .accessibility: analytics.capture(.permissionResult(permission: .accessibility, granted: accessibilityGranted))
        case .inputMonitoring: analytics.capture(.permissionResult(permission: .inputMonitoring, granted: inputMonitoringGranted))
        case .language, .analytics, .test: break
        }
        analytics.capture(.onboardingStepCompleted(step: step, seconds: Int(Date().timeIntervalSince(stepStarted))))
    }
}
