import AppKit

/// Invisible drop targets over each notch, or over the pill on screens without one.
/// Finder gives every drag its own pasteboard, so only a real drop target sees the files.
/// A full-screen probe peeks at each drag as it starts, then lets it pass through to the apps below.
/// Once a drag enters, the sensor grows over the open drop zone, so one window takes the drag from entry to drop.
/// Sensors sit above the indicator, since a drag goes to the top window even when it ignores the mouse.
@MainActor
final class DropSensor {
    private let onInvite: (NSScreen) -> Void
    private let onEnter: (NSScreen) -> Bool
    private let onDrop: (URL) -> Void
    private var panels: [SensorPanel] = []
    private var probes: [SensorPanel] = []
    private var isDragging = false
    private var dragMonitor: Any?
    private var screenObserver: NSObjectProtocol?

    init(onInvite: @escaping (NSScreen) -> Void, onEnter: @escaping (NSScreen) -> Bool, onDrop: @escaping (URL) -> Void) {
        self.onInvite = onInvite
        self.onEnter = onEnter
        self.onDrop = onDrop
    }

    func start() {
        guard dragMonitor == nil else { return }
        rebuild()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
            MainActor.assumeIsolated { self?.mouseDragging(event.type == .leftMouseDragged) }
        }
    }

    private func rebuild() {
        (panels + probes).forEach { $0.orderOut(nil) }
        panels = NSScreen.screens.map { screen in
            let layout = IndicatorLayout.make(screen: ScreenResolver.metrics(for: screen))
            let panel = SensorPanel(frame: layout.dropSensorFrame, zone: layout.windowFrame, level: 4)
            panel.contentView = SensorView(onEnter: onEnter, onDrop: onDrop)
            panel.orderFrontRegardless()
            return panel
        }
        probes = NSScreen.screens.map { screen in
            let probe = SensorPanel(frame: screen.frame, zone: screen.frame, level: 1)
            probe.contentView = ProbeView(onInvite: onInvite)
            probe.orderFrontRegardless()
            return probe
        }
    }

    // Sensors only listen during a drag, so clicks reach the indicator and the apps below
    private func mouseDragging(_ dragging: Bool) {
        guard dragging != isDragging else { return }
        isDragging = dragging
        for panel in panels + probes {
            panel.ignoresMouseEvents = !dragging
        }
    }
}

private final class SensorPanel: NSPanel {
    private let restingFrame: CGRect
    private let zoneFrame: CGRect

    init(frame: CGRect, zone: CGRect, level aboveMenu: Int) {
        restingFrame = frame
        zoneFrame = zone
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + aboveMenu)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func coverZone() {
        setFrame(zoneFrame, display: false)
    }

    func rest() {
        setFrame(restingFrame, display: false)
    }
}

private final class SensorView: NSView {
    private let onEnter: (NSScreen) -> Bool
    private let onDrop: (URL) -> Void
    private var isAccepting = false

    init(onEnter: @escaping (NSScreen) -> Bool, onDrop: @escaping (URL) -> Void) {
        self.onEnter = onEnter
        self.onDrop = onDrop
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { nil }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        isAccepting = false
        guard let screen = window?.screen, media(in: sender) != nil, onEnter(screen) else { return [] }
        isAccepting = true
        sensorPanel?.coverZone()
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        isAccepting ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        sensorPanel?.rest()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        sensorPanel?.rest()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard isAccepting, let media = media(in: sender) else { return false }
        onDrop(media)
        return true
    }

    private var sensorPanel: SensorPanel? { window as? SensorPanel }
}

private final class ProbeView: NSView {
    private let onInvite: (NSScreen) -> Void

    init(onInvite: @escaping (NSScreen) -> Void) {
        self.onInvite = onInvite
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { nil }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        window?.ignoresMouseEvents = true
        if let screen = window?.screen, media(in: sender) != nil { onInvite(screen) }
        return []
    }
}

@MainActor private func media(in drag: NSDraggingInfo) -> URL? {
    let files = drag.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    return files.first(where: MediaFile.isSupported)
}
