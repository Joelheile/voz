import Foundation
import ServiceManagement

enum LaunchAgent {
    static let label = "com.joelheile.voz.relaunch"
    static let installedPath = "/Applications/voz.app"

    private static var service: SMAppService { SMAppService.agent(plistName: "\(label).plist") }

    static var isInstalledCopy: Bool { Bundle.main.bundlePath == installedPath }
    static var launchedByLaunchd: Bool { ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"] == label }

    static func unregisterIfRegistered() {
        guard isInstalledCopy, service.status != .notRegistered, service.status != .notFound else { return }
        removeLegacyLoginItem()
        do {
            try service.unregister()
        } catch {
            Log.app.error("Launch agent unregister failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    static func bootOut() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["bootout", "gui/\(getuid())/\(label)"]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            Log.app.error("launchctl bootout failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    static func handOver() async -> Bool {
        guard isInstalledCopy, !launchedByLaunchd else { return false }
        removeLegacyLoginItem()
        do {
            if service.status != .notRegistered, service.status != .notFound {
                try await service.unregister()
            }
            try service.register()
        } catch {
            Log.app.error("Launch agent register failed: \(error.localizedDescription, privacy: .private)")
            return false
        }
        Log.app.notice("Launch agent registered, status \(service.status.rawValue)")
        for _ in 0..<20 {
            if isJobRunning { return true }
            try? await Task.sleep(for: .milliseconds(200))
        }
        Log.app.error("Launch agent did not start, staying unmanaged")
        return false
    }

    private static var isJobRunning: Bool {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print", "gui/\(getuid())/\(label)"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            Log.app.error("launchctl print failed: \(error.localizedDescription, privacy: .private)")
            return false
        }
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return text.contains("\tpid = ")
    }

    private static func removeLegacyLoginItem() {
        let legacy = SMAppService.mainApp
        guard legacy.status == .enabled else { return }
        do {
            try legacy.unregister()
        } catch {
            Log.app.error("Login item removal failed: \(error.localizedDescription, privacy: .private)")
        }
    }
}
