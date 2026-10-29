import CoreGraphics

struct ScreenMetrics: Equatable, Sendable {
    let frame: CGRect
    let notchSize: CGSize?
    let menuBarHeight: CGFloat

    init(
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

struct IndicatorLayout: Equatable, Sendable {
    enum Style: Equatable, Sendable {
        case notch
        case floating
    }

    static let minimumMenuBarHeight: CGFloat = 24
    static let sideWidth: CGFloat = 68
    static let seamOverlap: CGFloat = 1
    static let pillSize = CGSize(width: 108, height: 32)
    static let pillGap: CGFloat = 8
    static let shadowMargin: CGFloat = 16
    static let dropSwell: CGFloat = 6
    static let dropShadowRoom: CGFloat = 32

    let style: Style
    let panelFrame: CGRect
    let collapsedWidth: CGFloat

    static let previewWidth: CGFloat = 320
    static let previewHeight: CGFloat = 120

    var windowFrame: CGRect {
        let width = max(panelFrame.width + 2 * (Self.dropSwell + Self.dropShadowRoom), Self.previewWidth + 2 * Self.shadowMargin)
        return CGRect(
            x: panelFrame.midX - width / 2,
            y: panelFrame.minY - Self.previewHeight,
            width: width,
            height: panelFrame.height + Self.previewHeight
        )
    }

    static func make(screen: ScreenMetrics) -> IndicatorLayout {
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

enum ScreenChoice {
    static func index(containing windowFrame: CGRect, in screenFrames: [CGRect]) -> Int? {
        var best: (index: Int, area: CGFloat)?
        for (index, frame) in screenFrames.enumerated() {
            let overlap = frame.intersection(windowFrame)
            let area = overlap.isNull ? 0 : overlap.width * overlap.height
            if area > (best?.area ?? 0) { best = (index, area) }
        }
        return best?.index
    }
}

enum LevelBarsGeometry {
    static let barCount = 10
    static let barWidth: CGFloat = 3
    static let barSpacing: CGFloat = 2
    static let minHeight: CGFloat = 2
    static let maxHeight: CGFloat = 20
    static let secondsPerBar = 0.1
    static let loudnessExponent = 0.7
    static let trailingInset: CGFloat = 6
    static let pitch = barWidth + barSpacing
    static let visibleWidth = CGFloat(barCount) * pitch - barSpacing
    static let taperWidth = visibleWidth / 3

    static func height(level: Float, taper: CGFloat) -> CGFloat {
        minHeight + (maxHeight - minHeight) * loudness(level) * taper
    }

    static func taper(slot: Int, time: Double) -> CGFloat {
        let center = CGFloat(slot - 1) * pitch + barWidth / 2 + scrollOffset(time: time)
        let progress = min(max(center / taperWidth, 0), 1)
        return progress * progress * (3 - 2 * progress)
    }

    static func scrollOffset(time: Double) -> CGFloat {
        let progress = time / secondsPerBar
        return -CGFloat(progress - progress.rounded(.down)) * pitch
    }

    static func sampleWindow(slot: Int, time: Double) -> ClosedRange<Double> {
        let tickEnd = ((time / secondsPerBar).rounded(.down) + 1 - Double(barCount - slot)) * secondsPerBar
        return (tickEnd - secondsPerBar)...min(tickEnd, time)
    }

    private static func loudness(_ level: Float) -> CGFloat {
        CGFloat(pow(Double(min(max(level, 0), 1)), loudnessExponent))
    }
}
