import AVFoundation
import Combine
import Foundation
import VozCore

@MainActor
final class SetupModel: ObservableObject {
    @Published private(set) var microphoneStatus = Permissions.microphoneStatus
    @Published private(set) var accessibilityGranted = Permissions.accessibilityGranted
    @Published private(set) var inputMonitoringGranted = Permissions.inputMonitoringGranted

    private let analytics: Analytics

    init(analytics: Analytics) {
        self.analytics = analytics
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

    func reportPermissions() {
        refreshPermissions()
        analytics.capture(.permissionResult(permission: .microphone, granted: microphoneGranted))
        analytics.capture(.permissionResult(permission: .accessibility, granted: accessibilityGranted))
        analytics.capture(.permissionResult(permission: .inputMonitoring, granted: inputMonitoringGranted))
    }
}
