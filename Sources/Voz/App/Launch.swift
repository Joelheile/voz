import AppKit
import ServiceManagement

enum LoginItem {
    static let installedPath = "/Applications/voz.app"
    private static let legacyAgentPlist = "com.joelheile.voz.relaunch.plist"

    static var isInstalledCopy: Bool { Bundle.main.bundlePath == installedPath }
    static var isInTrash: Bool { Bundle.main.bundlePath.contains("/.Trash/") }

    /// Read during launch, while the open event macOS sent is still the current one.
    static var launchedAtLogin: Bool {
        let event = NSAppleEventManager.shared().currentAppleEvent
        return event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    /// Only the copy in Applications opens at login, so a build elsewhere never takes over.
    static func sync(enabled: Bool) {
        guard isInstalledCopy else { return }
        removeLegacyAgent()
        enabled ? register() : unregister()
    }

    static func unregister() {
        let service = SMAppService.mainApp
        guard service.status == .enabled || service.status == .requiresApproval else { return }
        do {
            try service.unregister()
        } catch {
            Log.app.error("Login item unregister failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    private static func register() {
        let service = SMAppService.mainApp
        guard service.status != .enabled else { return }
        do {
            try service.register()
        } catch {
            Log.app.error("Login item register failed: \(error.localizedDescription, privacy: .private)")
            Analytics.report(.loginItemFailed, cause: error)
        }
    }

    /// Older versions kept voz alive with a launch agent, which could restart the old copy during an update.
    private static func removeLegacyAgent() {
        let agent = SMAppService.agent(plistName: legacyAgentPlist)
        guard agent.status != .notRegistered, agent.status != .notFound else { return }
        do {
            try agent.unregister()
        } catch {
            Log.app.error("Launch agent unregister failed: \(error.localizedDescription, privacy: .private)")
        }
    }
}

@MainActor
enum AppMover {
    static var shouldOffer: Bool {
        #if DEBUG
        false
        #else
        !LoginItem.isInstalledCopy
        #endif
    }

    /// A copy on a disk image or in a translocated folder can't run for long, so it moves without asking.
    static func offer() {
        let source = Bundle.main.bundleURL
        let readOnly = (try? source.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly) == true
        guard readOnly || confirm() else { return }
        let diskImage = readOnly ? mountedDiskImage(holding: source) : nil
        do {
            try moveToApplications(from: source, keepSource: readOnly)
        } catch {
            Log.app.error("Move to Applications failed: \(error.localizedDescription, privacy: .private)")
            showFailure(error)
            return
        }
        relaunchAfterExit(URL(fileURLWithPath: LoginItem.installedPath), ejecting: diskImage)
        exit(0)
    }

    private static func confirm() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Move Voz to Applications?"
        alert.informativeText = "Voz starts at login and updates itself only from the Applications folder."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not now")
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func moveToApplications(from source: URL, keepSource: Bool) throws {
        let fileManager = FileManager.default
        let destination = URL(fileURLWithPath: LoginItem.installedPath)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.trashItem(at: destination, resultingItemURL: nil)
        }
        try fileManager.copyItem(at: source, to: destination)
        clearQuarantine(destination)
        guard !keepSource else { return }
        try fileManager.trashItem(at: source, resultingItemURL: nil)
    }

    /// You already approved this download when you opened it, so the copy shouldn't ask again.
    private static func clearQuarantine(_ app: URL) {
        let paths = [app.path] + (FileManager.default.enumerator(atPath: app.path)?.compactMap { $0 as? String }.map { app.appendingPathComponent($0).path } ?? [])
        for path in paths {
            removexattr(path, "com.apple.quarantine", XATTR_NOFOLLOW)
        }
    }

    /// Translocation hides the original path, so this finds the read-only volume that holds a copy of Voz.
    private static func mountedDiskImage(holding source: URL) -> URL? {
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeIsReadOnlyKey], options: [.skipHiddenVolumes]) ?? []
        return volumes.first { volume in
            volume.path != "/"
                && (try? volume.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly) == true
                && FileManager.default.fileExists(atPath: volume.appendingPathComponent(source.lastPathComponent).path)
        }
    }

    static func relaunchAfterExit(_ app: URL, ejecting volume: URL? = nil) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.1; done; [ -n \"$3\" ] && hdiutil detach -quiet \"$3\"; open \"$2\"",
            "sh", String(getpid()), app.path, volume?.path ?? "",
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

    func claim() throws -> Bool {
        let path = try AppStorage.directory().appendingPathComponent("instance.lock").path
        descriptor = open(path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            descriptor = -1
            return false
        }
        return true
    }
}

enum OpenRequest {
    private static let name = Notification.Name("\(Bundle.main.bundleIdentifier ?? SystemContext.bundleID).open")

    static func send() {
        DistributedNotificationCenter.default().postNotificationName(name, object: nil, userInfo: nil, deliverImmediately: true)
    }

    @MainActor
    static func observe(_ handler: @escaping @MainActor () -> Void) {
        DistributedNotificationCenter.default().addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated(handler)
        }
    }
}

/// Identifies the bundle at a path, so a swap that leaves the path in place still counts as a change.
struct BundleIdentity: Equatable {
    private let device: dev_t
    private let inode: ino_t

    init?(path: String) {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        device = info.st_dev
        inode = info.st_ino
    }
}

@MainActor
final class UninstallWatcher {
    private static let settleDelay: TimeInterval = 2

    private let launchedBundle = BundleIdentity(path: Bundle.main.bundlePath)
    private var source: DispatchSourceFileSystemObject?

    func start() {
        guard LoginItem.isInstalledCopy else { return }
        let descriptor = open(LoginItem.installedPath, O_EVTONLY)
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
        // A run loop timer, not a Task: terminating from a main queue job deadlocks the delayed terminate reply.
        Timer.scheduledTimer(withTimeInterval: Self.settleDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.bundleSettled() }
        }
    }

    private func bundleSettled() {
        guard let installed = BundleIdentity(path: LoginItem.installedPath) else { return quit() }
        guard installed != launchedBundle else { return start() }
        restartIntoReplacement()
    }

    private func quit() {
        Log.app.notice("App moved out of Applications, quitting")
        LoginItem.unregister()
        NSApp.terminate(nil)
    }

    private func restartIntoReplacement() {
        Log.app.notice("A new copy replaced the app, restarting")
        AppMover.relaunchAfterExit(URL(fileURLWithPath: LoginItem.installedPath))
        NSApp.terminate(nil)
    }
}
