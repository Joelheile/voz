import AppKit

enum MenuBarNotch {
    static let hint = "The Voz icon is behind the notch. Hold ⌘ and drag other menu bar icons out to make room."

    static func hides(_ item: NSRect, on screen: NSScreen) -> Bool {
        guard let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return false }
        return hides(item, screen: screen.frame, leftWidth: left.width, rightWidth: right.width)
    }

    static func hides(_ item: NSRect, screen: NSRect, leftWidth: CGFloat, rightWidth: CGFloat) -> Bool {
        let notch = (screen.minX + leftWidth)...(screen.maxX - rightWidth)
        return notch.contains(item.midX)
    }
}
