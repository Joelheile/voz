import AVFoundation
import AppKit
import ApplicationServices

@MainActor
enum Permissions {
    static var accessibilityGranted: Bool { AXIsProcessTrusted() }

    static func promptForAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func requestMicrophone() async {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined else { return }
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        Log.app.notice("Microphone access granted: \(granted)")
    }

    static var microphoneStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    static var inputMonitoringGranted: Bool { CGPreflightListenEventAccess() }

    static func requestInputMonitoring() {
        CGRequestListenEventAccess()
    }

    static var systemAudioGranted: Bool { SystemAudioAccess.preflight() == 0 }

    static func requestSystemAudio() async {
        guard !systemAudioGranted else { return }
        let granted = await SystemAudioAccess.request()
        Log.app.notice("System audio access granted: \(granted)")
        if !granted { openSettings(.systemAudio) }
    }

    enum PrivacyPane: String {
        case microphone = "Privacy_Microphone"
        case inputMonitoring = "Privacy_ListenEvent"
        case systemAudio = "Privacy_ScreenCapture"
    }

    static func openSettings(_ pane: PrivacyPane) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane.rawValue)") else { return }
        NSWorkspace.shared.open(url)
    }

    static var microphoneGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
}
