import CoreGraphics

struct IndicatorLayout: Equatable, Sendable {
    static let pillSize = CGSize(width: 108, height: 32)
    static let pillGap: CGFloat = 8
    static let bottomGap: CGFloat = 16
    static let shadowMargin: CGFloat = 16
    static let previewWidth: CGFloat = 320
    static let previewHeight: CGFloat = 120

    let panelFrame: CGRect

    var windowFrame: CGRect {
        let width = max(panelFrame.width, Self.previewWidth + 2 * Self.shadowMargin)
        return CGRect(
            x: panelFrame.midX - width / 2,
            y: panelFrame.minY,
            width: width,
            height: panelFrame.height + Self.previewHeight
        )
    }

    /// Centers the pill just above the Dock, like Wispr Flow. The preview grows upward.
    static func make(visibleFrame: CGRect) -> IndicatorLayout {
        let pill = CGRect(
            x: visibleFrame.midX - pillSize.width / 2,
            y: visibleFrame.minY + bottomGap,
            width: pillSize.width,
            height: pillSize.height
        )
        return IndicatorLayout(panelFrame: pill.insetBy(dx: -shadowMargin, dy: -shadowMargin))
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
