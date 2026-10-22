import AppKit

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
