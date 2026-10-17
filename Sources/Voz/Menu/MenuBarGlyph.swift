import AppKit
import VozCore

enum MenuBarGlyph {
    private static let size = NSSize(width: 18, height: 18)
    private static let barWidth: CGFloat = 2.5
    private static let barSpacing: CGFloat = 2
    private static let idleHeights: [CGFloat] = [6, 11, 15, 9]
    private static let flatHeights: [CGFloat] = [4, 4, 4, 4]

    static func image(for phase: DictationPhase) -> NSImage {
        let heights = phase == .transcribing ? flatHeights : idleHeights
        let color = phase == .recording ? Theme.accentNSColor : NSColor.black
        let image = NSImage(size: size, flipped: false) { rect in
            color.setFill()
            let total = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * barSpacing
            var x = (rect.width - total) / 2
            for height in heights {
                let bar = NSRect(x: x, y: (rect.height - height) / 2, width: barWidth, height: height)
                NSBezierPath(roundedRect: bar, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
                x += barWidth + barSpacing
            }
            return true
        }
        image.isTemplate = phase != .recording
        return image
    }
}
