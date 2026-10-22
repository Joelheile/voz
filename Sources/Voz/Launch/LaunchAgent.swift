import Foundation
import ServiceManagement

enum LaunchAgent {
    static let label = "com.joelheile.voz.relaunch"
    static let installedPath = "/Applications/voz.app"
    private static let startAttempts = 3

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
        for attempt in 1...startAttempts {
            if await startJob() { return true }
            Log.app.error("Launch agent did not start voz, attempt \(attempt)")
            unregisterIfRegistered()
            try? await Task.sleep(for: .seconds(1))
        }
        Log.app.error("Launch agent failed, staying unmanaged")
        return false
    }

    private static func startJob() async -> Bool {
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
            if jobRunsVoz { return true }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return false
    }

    private static var jobRunsVoz: Bool {
        guard let pid = jobPID, let executable = Bundle.main.executablePath else { return false }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return false }
        return String(cString: buffer) == executable
    }

    private static var jobPID: Int32? {
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
            return nil
        }
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        let line = text.split(separator: "\n").first { $0.hasPrefix("\tpid = ") }
        return line.flatMap { Int32($0.dropFirst("\tpid = ".count)) }
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
