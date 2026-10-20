import CoreGraphics

public enum IndicatorStyle: String, CaseIterable, Sendable {
    case notch
    case pill
}

public struct ScreenMetrics: Equatable, Sendable {
    public let frame: CGRect
    public let notchSize: CGSize?
    public let menuBarHeight: CGFloat

    public init(frame: CGRect, notchSize: CGSize?, menuBarHeight: CGFloat) {
        self.frame = frame
        self.notchSize = notchSize
        self.menuBarHeight = menuBarHeight
    }

    public init(
        frame: CGRect,
        safeAreaTop: CGFloat,
        leftAreaWidth: CGFloat?,
        rightAreaWidth: CGFloat?,
        visibleMaxY: CGFloat
    ) {
        var notchSize: CGSize?
        if safeAreaTop > 0, let leftAreaWidth, let rightAreaWidth {
            notchSize = CGSize(width: frame.width - leftAreaWidth - rightAreaWidth, height: safeAreaTop)
        }
        let menuBarHeight = notchSize?.height ?? max(frame.maxY - visibleMaxY, IndicatorLayout.minimumMenuBarHeight)
        self.init(frame: frame, notchSize: notchSize, menuBarHeight: menuBarHeight)
    }
}

public struct IndicatorLayout: Equatable, Sendable {
    public static let minimumMenuBarHeight: CGFloat = 24
    public static let sideWidth: CGFloat = 56
    public static let seamOverlap: CGFloat = 1
    public static let pillSize = CGSize(width: 104, height: 30)
    public static let pillGap: CGFloat = 8

    public let style: IndicatorStyle
    public let panelFrame: CGRect
    public let collapsedWidth: CGFloat

    public static func make(style: IndicatorStyle, screen: ScreenMetrics) -> IndicatorLayout {
        if style == .notch, let notch = screen.notchSize {
            let size = CGSize(width: notch.width + 2 * sideWidth, height: notch.height)
            return IndicatorLayout(
                style: .notch,
                panelFrame: topCenteredFrame(size: size, topInset: 0, in: screen.frame),
                collapsedWidth: notch.width + 2 * seamOverlap
            )
        }
        return IndicatorLayout(
            style: .pill,
            panelFrame: topCenteredFrame(size: pillSize, topInset: screen.menuBarHeight + pillGap, in: screen.frame),
            collapsedWidth: pillSize.width
        )
    }

    private static func topCenteredFrame(size: CGSize, topInset: CGFloat, in screenFrame: CGRect) -> CGRect {
        CGRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - topInset - size.height,
            width: size.width,
            height: size.height
        )
    }
}

public enum ScreenChoice {
    public static func index(containing windowFrame: CGRect, in screenFrames: [CGRect]) -> Int? {
        var best: (index: Int, area: CGFloat)?
        for (index, frame) in screenFrames.enumerated() {
            let overlap = frame.intersection(windowFrame)
            let area = overlap.isNull ? 0 : overlap.width * overlap.height
            if area > (best?.area ?? 0) { best = (index, area) }
        }
        return best?.index
    }
}
