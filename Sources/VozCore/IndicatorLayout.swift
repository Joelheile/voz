import CoreGraphics

public struct ScreenMetrics: Equatable, Sendable {
    public let frame: CGRect
    public let notchSize: CGSize?
    public let menuBarHeight: CGFloat

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
        self.frame = frame
        self.notchSize = notchSize
        menuBarHeight = notchSize?.height ?? max(frame.maxY - visibleMaxY, IndicatorLayout.minimumMenuBarHeight)
    }
}

public struct IndicatorLayout: Equatable, Sendable {
    public enum Style: Equatable, Sendable {
        case notch
        case floating
    }

    public static let minimumMenuBarHeight: CGFloat = 24
    public static let sideWidth: CGFloat = 68
    public static let seamOverlap: CGFloat = 1
    public static let pillSize = CGSize(width: 108, height: 32)
    public static let pillGap: CGFloat = 8
    public static let shadowMargin: CGFloat = 16

    public let style: Style
    public let panelFrame: CGRect
    public let collapsedWidth: CGFloat

    public static func make(screen: ScreenMetrics) -> IndicatorLayout {
        guard let notch = screen.notchSize else { return floating(screen: screen) }
        let size = CGSize(width: notch.width + 2 * sideWidth, height: notch.height)
        return IndicatorLayout(
            style: .notch,
            panelFrame: CGRect(
                x: screen.frame.midX - size.width / 2,
                y: screen.frame.maxY - size.height,
                width: size.width,
                height: size.height
            ),
            collapsedWidth: notch.width + 2 * seamOverlap
        )
    }

    private static func floating(screen: ScreenMetrics) -> IndicatorLayout {
        let pill = CGRect(
            x: screen.frame.midX - pillSize.width / 2,
            y: screen.frame.maxY - screen.menuBarHeight - pillGap - pillSize.height,
            width: pillSize.width,
            height: pillSize.height
        )
        return IndicatorLayout(
            style: .floating,
            panelFrame: pill.insetBy(dx: -shadowMargin, dy: -shadowMargin),
            collapsedWidth: 0
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
