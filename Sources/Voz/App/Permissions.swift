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

    static func requestAccessibility() {
        PermissionTile.show(.accessibility) { accessibilityGranted }
    }

    static func requestInputMonitoring() {
        CGRequestListenEventAccess()
        PermissionTile.show(.inputMonitoring) { inputMonitoringGranted }
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
        case accessibility = "Privacy_Accessibility"
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

struct PermissionSnapshot: Equatable {
    let microphone: AVAuthorizationStatus
    let accessibility: Bool
    let inputMonitoring: Bool
    let systemAudio: Bool

    @concurrent static func read() async -> PermissionSnapshot {
        PermissionSnapshot(
            microphone: AVCaptureDevice.authorizationStatus(for: .audio),
            accessibility: AXIsProcessTrusted(),
            inputMonitoring: CGPreflightListenEventAccess(),
            systemAudio: SystemAudioAccess.preflight() == 0
        )
    }
}

enum SystemAudioAccess {
    private typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int
    private typealias Request = @convention(c) (CFString, CFDictionary?, @escaping (Bool) -> Void) -> Void

    private static let service = "kTCCServiceAudioCapture"
    nonisolated(unsafe) private static let framework = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)

    static func preflight() -> Int? {
        guard let symbol = symbol("TCCAccessPreflight") else { return nil }
        return unsafeBitCast(symbol, to: Preflight.self)(service as CFString, nil)
    }

    static func request() async -> Bool {
        guard let symbol = symbol("TCCAccessRequest") else { return false }
        let request = unsafeBitCast(symbol, to: Request.self)
        return await withCheckedContinuation { continuation in
            request(service as CFString, nil) { continuation.resume(returning: $0) }
        }
    }

    private static func symbol(_ name: String) -> UnsafeMutableRawPointer? {
        guard let framework, let symbol = dlsym(framework, name) else {
            Log.app.error("\(name, privacy: .public) unavailable")
            return nil
        }
        return symbol
    }
}
