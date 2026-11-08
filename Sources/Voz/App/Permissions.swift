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

    /// Clears grants left over from an older signature once per build, so macOS lists Voz again and asks once instead of at every launch
    static func repairStaleGrants() async {
        let defaults = UserDefaults.standard
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        guard defaults.string(forKey: StaleGrant.repairedBuildKey) != build else { return }
        defaults.set(build, forKey: StaleGrant.repairedBuildKey)
        if !inputMonitoringGranted {
            await StaleGrant.clear(.inputMonitoring)
            CGRequestListenEventAccess()
        }
        if !accessibilityGranted {
            await StaleGrant.clear(.accessibility)
            promptForAccessibility()
        }
    }

    static func requestAccessibility() {
        Task {
            await StaleGrant.clear(.accessibility)
            promptForAccessibility()
            PermissionTile.show(.accessibility) { accessibilityGranted }
        }
    }

    static func requestInputMonitoring() {
        Task {
            await StaleGrant.clear(.inputMonitoring)
            CGRequestListenEventAccess()
            PermissionTile.show(.inputMonitoring) { inputMonitoringGranted }
        }
    }

    /// A blocked microphone is often a grant from an older signature, so clear it and ask again before sending you to System Settings
    static func requestBlockedMicrophone() async {
        await StaleGrant.clear(.microphone)
        await requestMicrophone()
        if !microphoneGranted { openSettings(.microphone) }
    }

    static var systemAudioGranted: Bool { SystemAudioAccess.preflight() == 0 }

    static func requestSystemAudio() async {
        guard !systemAudioGranted else { return }
        await StaleGrant.clear(.systemAudio)
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

    static var microphoneUndecided: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined
    }
}

/// macOS ties each grant to the certificate that signed Voz. After an update signed differently, System Settings still shows Voz switched on,
/// but macOS ignores that entry and turning it on again does nothing. Resetting Voz's own entry lets macOS list it fresh.
enum StaleGrant {
    static let repairedBuildKey = "staleGrantsRepairedBuild"

    nonisolated static func arguments(for pane: Permissions.PrivacyPane, bundleID: String) -> [String] {
        let service = switch pane {
        case .microphone: "Microphone"
        case .accessibility: "Accessibility"
        case .inputMonitoring: "ListenEvent"
        case .systemAudio: "AudioCapture"
        }
        return ["reset", service, bundleID]
    }

    /// Only call this when the grant is missing: it also clears one that works
    @concurrent static func clear(_ pane: Permissions.PrivacyPane) async {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = arguments(for: pane, bundleID: bundleID)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            Log.app.error("Could not reset \(pane.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
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
