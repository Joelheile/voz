import AppKit
import VozCore

enum MenuBarGlyph {
    private static let height: CGFloat = 16
    private static let transcribingOpacity: CGFloat = 0.45

    private static let icon: NSImage = {
        guard let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            fatalError("MenuBarIcon.png missing from app bundle")
        }
        image.size = NSSize(width: (height * image.size.width / image.size.height).rounded(), height: height)
        return image
    }()

    private static let dimmedIcon = NSImage(size: icon.size, flipped: false) { rect in
        icon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: transcribingOpacity)
        return true
    }

    static func image(for phase: DictationPhase) -> NSImage {
        phase == .transcribing ? dimmedIcon : icon
    }
}
