import CoreGraphics

public enum LevelBarsGeometry {
    public static let barCount = 10
    public static let barWidth: CGFloat = 3
    public static let barSpacing: CGFloat = 2
    public static let minHeight: CGFloat = 2
    public static let maxHeight: CGFloat = 20
    public static let secondsPerBar = 0.1
    public static let loudnessExponent = 0.7
    public static let trailingInset: CGFloat = 6
    public static let pitch = barWidth + barSpacing
    public static let visibleWidth = CGFloat(barCount) * pitch - barSpacing
    public static let taperWidth = visibleWidth / 3

    public static func height(level: Float, taper: CGFloat) -> CGFloat {
        minHeight + (maxHeight - minHeight) * loudness(level) * taper
    }

    public static func taper(slot: Int, time: Double) -> CGFloat {
        let center = CGFloat(slot - 1) * pitch + barWidth / 2 + scrollOffset(time: time)
        let progress = min(max(center / taperWidth, 0), 1)
        return progress * progress * (3 - 2 * progress)
    }

    public static func scrollOffset(time: Double) -> CGFloat {
        let progress = time / secondsPerBar
        return -CGFloat(progress - progress.rounded(.down)) * pitch
    }

    public static func sampleWindow(slot: Int, time: Double) -> ClosedRange<Double> {
        let tickEnd = ((time / secondsPerBar).rounded(.down) + 1 - Double(barCount - slot)) * secondsPerBar
        return (tickEnd - secondsPerBar)...min(tickEnd, time)
    }

    private static func loudness(_ level: Float) -> CGFloat {
        CGFloat(pow(Double(min(max(level, 0), 1)), loudnessExponent))
    }
}
