import AppKit
import ServiceManagement

enum LaunchAgent {
    static let label = "com.joelheile.voz.relaunch"
    static let installedPath = "/Applications/voz.app"
    private static let startAttempts = 3

    private static var service: SMAppService { SMAppService.agent(plistName: "\(label).plist") }

    static var isInstalledCopy: Bool { Bundle.main.bundlePath == installedPath }
    static var launchedByLaunchd: Bool { ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"] == label }

    static var isInTrash: Bool { Bundle.main.bundlePath.contains("/.Trash/") }

    static func unregisterIfRegistered() {
        guard isInstalledCopy || isInTrash, service.status != .notRegistered, service.status != .notFound else { return }
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
            try? await Task.sleep(for: .milliseconds(200))
        }
        Log.app.error("Launch agent failed, staying unmanaged")
        Analytics.report(.launchAgentFailed)
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
            switch jobState {
            case .running: return true
            case .failed: return false
            case .starting: try? await Task.sleep(for: .milliseconds(200))
            }
        }
        return false
    }

    private enum JobState {
        case failed
        case starting
        case running
    }

    private static var jobState: JobState {
        guard let description = launchctlPrint() else { return .failed }
        let lines = description.split(separator: "\n")
        let exited = lines.contains { $0.hasPrefix("\tlast exit code = ") && !$0.hasSuffix("(never exited)") }
        guard !exited else { return .failed }
        let line = lines.first { $0.hasPrefix("\tpid = ") }
        guard let pid = line.flatMap({ Int32($0.dropFirst("\tpid = ".count)) }), let executable = Bundle.main.executablePath else { return .starting }
        var buffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return .starting }
        return String(decoding: buffer.prefix(while: { $0 != 0 }), as: UTF8.self) == executable ? .running : .starting
    }

    private static func launchctlPrint() -> String? {
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
        return process.terminationStatus == 0 ? text : nil
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

@MainActor
enum AppMover {
    static var shouldOffer: Bool {
        #if DEBUG
        false
        #else
        !LaunchAgent.isInstalledCopy
        #endif
    }

    static func offer() {
        guard confirm() else { return }
        do {
            try moveToApplications()
        } catch {
            Log.app.error("Move to Applications failed: \(error.localizedDescription, privacy: .private)")
            showFailure(error)
            return
        }
        relaunchAfterExit(URL(fileURLWithPath: LaunchAgent.installedPath))
        exit(0)
    }

    private static var isTranslocated: Bool { Bundle.main.bundlePath.contains("/AppTranslocation/") }

    private static func confirm() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Move Voz to Applications?"
        alert.informativeText = "Voz starts at login and updates itself only from the Applications folder."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not now")
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func moveToApplications() throws {
        let fileManager = FileManager.default
        let source = Bundle.main.bundleURL
        let destination = URL(fileURLWithPath: LaunchAgent.installedPath)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.trashItem(at: destination, resultingItemURL: nil)
        }
        try fileManager.copyItem(at: source, to: destination)
        guard !isTranslocated else { return }
        try fileManager.trashItem(at: source, resultingItemURL: nil)
    }

    private static func relaunchAfterExit(_ app: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.1; done; open \"$2\"",
            "sh", String(getpid()), app.path,
        ]
        do {
            try process.run()
        } catch {
            Log.app.error("Relaunch failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    private static func showFailure(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Voz couldn't move itself"
        alert.informativeText = "Drag voz.app to the Applications folder in Finder. \(error.localizedDescription)"
        alert.runModal()
    }
}

final class SingleInstance {
    private var descriptor: Int32 = -1

    func claim(waiting: Duration) throws -> Bool {
        let path = try AppStorage.directory().appendingPathComponent("instance.lock").path
        descriptor = open(path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let deadline = ContinuousClock.now + waiting
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            guard ContinuousClock.now < deadline else {
                close(descriptor)
                descriptor = -1
                return false
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return true
    }
}

enum OpenRequest {
    private static let name = Notification.Name("com.joelheile.voz.open")
    private static let pendingKey = "openPanelOnNextLaunch"

    static func send() {
        DistributedNotificationCenter.default().postNotificationName(name, object: nil, userInfo: nil, deliverImmediately: true)
    }

    @MainActor
    static func observe(_ handler: @escaping @MainActor () -> Void) {
        DistributedNotificationCenter.default().addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated(handler)
        }
    }

    static func deferToNextLaunch() {
        UserDefaults.standard.set(true, forKey: pendingKey)
    }

    static func takePending() -> Bool {
        defer { UserDefaults.standard.removeObject(forKey: pendingKey) }
        return UserDefaults.standard.bool(forKey: pendingKey)
    }
}

@MainActor
final class UninstallWatcher {
    private static let settleDelay: Duration = .seconds(2)

    private var source: DispatchSourceFileSystemObject?

    func start() {
        guard LaunchAgent.isInstalledCopy else { return }
        let descriptor = open(LaunchAgent.installedPath, O_EVTONLY)
        guard descriptor >= 0 else {
            Log.app.error("Could not watch the app bundle for removal")
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.delete, .rename], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.bundleMoved() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    private func bundleMoved() {
        source?.cancel()
        source = nil
        Task {
            try? await Task.sleep(for: Self.settleDelay)
            guard !FileManager.default.fileExists(atPath: LaunchAgent.installedPath) else { return start() }
            Log.app.notice("App moved out of Applications, quitting")
            LaunchAgent.bootOut()
            NSApp.terminate(nil)
        }
    }
}
