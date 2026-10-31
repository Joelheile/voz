import AppKit

enum MenuBarNotch {
    static let hint = "The Voz icon is behind the notch. Hold ⌘ and drag other menu bar icons out to make room."
    private static let savedPositionKey = "NSStatusItem Preferred Position Item-0"
    private static let iconSpanFromSavedPosition: CGFloat = 54
    private static let micIndicatorWidth: CGFloat = 48

    static func hides(_ item: NSRect, on screen: NSScreen) -> Bool {
        guard let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return false }
        return hides(item, screen: screen.frame, leftWidth: left.width, rightWidth: right.width)
    }

    static func hides(_ item: NSRect, screen: NSRect, leftWidth: CGFloat, rightWidth: CGFloat) -> Bool {
        let notch = (screen.minX + leftWidth)...(screen.maxX - rightWidth)
        return notch.contains(item.midX)
    }

    static func hides(savedPosition: CGFloat?, rightWidth: CGFloat) -> Bool {
        guard let savedPosition else { return true }
        return savedPosition > positionBesideNotch(rightWidth: rightWidth)
    }

    static func positionBesideNotch(rightWidth: CGFloat) -> CGFloat {
        rightWidth - iconSpanFromSavedPosition - micIndicatorWidth
    }

    static func placeIconBesideNotch() {
        guard let rightWidth = NSScreen.screens.compactMap(\.auxiliaryTopRightArea?.width).min() else { return }
        let defaults = UserDefaults.standard
        let savedPosition = (defaults.object(forKey: savedPositionKey) as? NSNumber).map { CGFloat($0.doubleValue) }
        guard hides(savedPosition: savedPosition, rightWidth: rightWidth) else { return }
        defaults.set(Double(positionBesideNotch(rightWidth: rightWidth)), forKey: savedPositionKey)
    }
}
