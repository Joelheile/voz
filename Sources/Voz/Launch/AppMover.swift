import AppKit

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
