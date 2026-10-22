import AppKit
import SwiftUI

@MainActor
enum PermissionTile {
    private static let settingsBundleID = "com.apple.systempreferences"
    private static let followInterval: TimeInterval = 0.2
    private static let settingsLaunchGrace: TimeInterval = 5
    private static let gap: CGFloat = 8

    private static var panel: TilePanel?
    private static var follow: Timer?

    static func show(_ pane: Permissions.PrivacyPane, granted: @escaping @MainActor () -> Bool) {
        close()
        Permissions.openSettings(pane)
        let panel = TilePanel(rootView: PermissionTileView(close: close))
        self.panel = panel
        let openedAt = Date()
        follow = Timer.scheduledTimer(withTimeInterval: followInterval, repeats: true) { _ in
            MainActor.assumeIsolated { update(panel, granted: granted, openedAt: openedAt) }
        }
    }

    static func close() {
        follow?.invalidate()
        follow = nil
        panel?.close()
        panel = nil
    }

    private static func update(_ panel: TilePanel, granted: () -> Bool, openedAt: Date) {
        if granted() { return close() }
        guard let window = settingsWindow() else {
            let settingsHadTimeToOpen = Date().timeIntervalSince(openedAt) > settingsLaunchGrace
            if settingsHadTimeToOpen || panel.isVisible { close() }
            return
        }
        let screen = NSScreen.screens.first { $0.frame.intersects(window.frame) }?.visibleFrame ?? window.frame
        panel.setFrameOrigin(origin(for: panel.frame.size, below: window.frame, on: screen))
        panel.order(.above, relativeTo: window.number)
    }

    static func origin(for tile: CGSize, below window: CGRect, on screen: CGRect) -> CGPoint {
        let x = min(max(window.midX - tile.width / 2, screen.minX + gap), screen.maxX - tile.width - gap)
        let below = window.minY - gap - tile.height
        let insideBottom = window.minY + gap * 2
        return CGPoint(x: x, y: below >= screen.minY ? below : insideBottom)
    }

    private static func settingsWindow() -> (frame: CGRect, number: Int)? {
        guard let settings = NSRunningApplication.runningApplications(withBundleIdentifier: settingsBundleID).first,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let window = windows.first(where: {
                  $0[kCGWindowOwnerPID as String] as? pid_t == settings.processIdentifier && $0[kCGWindowLayer as String] as? Int == 0
              }),
              let number = window[kCGWindowNumber as String] as? Int,
              let bounds = window[kCGWindowBounds as String] as? NSDictionary,
              let topLeftFrame = CGRect(dictionaryRepresentation: bounds)
        else { return nil }
        return (cocoaFrame(fromTopLeft: topLeftFrame, primaryScreenHeight: NSScreen.screens.first?.frame.height ?? 0), number)
    }

    static func cocoaFrame(fromTopLeft frame: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: primaryScreenHeight - frame.maxY, width: frame.width, height: frame.height)
    }
}

private final class TilePanel: NSPanel {
    init(rootView: PermissionTileView) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let hosting = NSHostingView(rootView: rootView)
        contentView = hosting
        setContentSize(hosting.fittingSize)
    }
}

struct PermissionTileView: View {
    let close: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AppDragSource().frame(width: 40, height: 40).help("Drag into the list")
            VStack(alignment: .leading, spacing: 2) {
                Text("Drag Voz into the list above")
                    .font(.ui(13, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Text("Then turn it on. Already listed? Just turn it on.")
                    .font(.meta)
                    .foregroundStyle(Theme.inkSecondary)
            }
            Button(action: close) { Icon(.x, size: 12) }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.inkTertiary)
                .help("Close")
        }
        .padding(12)
        .fixedSize()
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous).strokeBorder(Theme.hairline))
    }
}

private struct AppDragSource: NSViewRepresentable {
    func makeNSView(context: Context) -> AppDragView { AppDragView() }
    func updateNSView(_ view: AppDragView, context: Context) {}
}

private final class AppDragView: NSImageView, NSDraggingSource {
    init() {
        super.init(frame: .zero)
        image = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        imageScaling = .scaleProportionallyUpOrDown
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let item = NSDraggingItem(pasteboardWriter: Bundle.main.bundleURL as NSURL)
        item.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}
