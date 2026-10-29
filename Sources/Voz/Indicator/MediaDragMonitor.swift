import AppKit

@MainActor
final class MediaDragMonitor {
    private static let releaseCheckInterval = 0.1

    private let isEnabled: () -> Bool
    private let onStart: () -> Void
    private let onEnd: () -> Void
    private var monitor: Any?
    private var releaseCheck: Timer?
    private var lastChange = NSPasteboard(name: .drag).changeCount

    init(isEnabled: @escaping () -> Bool, onStart: @escaping () -> Void, onEnd: @escaping () -> Void) {
        self.isEnabled = isEnabled
        self.onStart = onStart
        self.onEnd = onEnd
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            MainActor.assumeIsolated { self?.dragged() }
        }
    }

    private func dragged() {
        let pasteboard = NSPasteboard(name: .drag)
        guard releaseCheck == nil, pasteboard.changeCount != lastChange else { return }
        lastChange = pasteboard.changeCount
        guard isEnabled(), Self.carriesMedia(pasteboard) else { return }
        onStart()
        let timer = Timer(timeInterval: Self.releaseCheckInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkRelease() }
        }
        RunLoop.main.add(timer, forMode: .common)
        releaseCheck = timer
    }

    private func checkRelease() {
        guard NSEvent.pressedMouseButtons & 1 == 0 else { return }
        releaseCheck?.invalidate()
        releaseCheck = nil
        onEnd()
    }

    private static func carriesMedia(_ pasteboard: NSPasteboard) -> Bool {
        let files = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return files.contains(where: MediaFile.isSupported)
    }
}
