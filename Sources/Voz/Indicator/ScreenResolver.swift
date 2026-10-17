import AppKit
import VozCore

enum ScreenResolver {
    @MainActor
    static func targetScreen() -> NSScreen? {
        screenOfFrontmostWindow() ?? screenUnderMouse() ?? NSScreen.main ?? NSScreen.screens.first
    }

    @MainActor
    static func metrics(for screen: NSScreen) -> ScreenMetrics {
        ScreenMetrics(
            frame: screen.frame,
            safeAreaTop: screen.safeAreaInsets.top,
            leftAreaWidth: screen.auxiliaryTopLeftArea?.width,
            rightAreaWidth: screen.auxiliaryTopRightArea?.width,
            visibleMaxY: screen.visibleFrame.maxY
        )
    }

    @MainActor
    private static func screenOfFrontmostWindow() -> NSScreen? {
        guard
            let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
            let primaryHeight = NSScreen.screens.first?.frame.height,
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        for window in windows {
            guard
                window[kCGWindowOwnerPID as String] as? pid_t == pid,
                window[kCGWindowLayer as String] as? Int == 0,
                let boundsDictionary = window[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDictionary)
            else { continue }
            let cocoaFrame = CGRect(x: bounds.minX, y: primaryHeight - bounds.maxY, width: bounds.width, height: bounds.height)
            let screens = NSScreen.screens
            if let index = ScreenChoice.index(containing: cocoaFrame, in: screens.map(\.frame)) {
                return screens[index]
            }
        }
        return nil
    }

    @MainActor
    private static func screenUnderMouse() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) }
    }
}
