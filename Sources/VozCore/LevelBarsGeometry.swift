import CoreGraphics

public enum LevelBarsGeometry {
    public static let barCount = 11
    public static let barWidth: CGFloat = 2
    public static let barSpacing: CGFloat = 2
    public static let minHeight: CGFloat = 2
    public static let maxHeight: CGFloat = 20
    public static let secondsPerBar = 0.05
    public static let latency = 0.02
    public static let loudnessExponent = 0.7
    public static let trailingInset: CGFloat = 6
    public static let pitch = barWidth + barSpacing
    public static let visibleWidth = CGFloat(barCount) * pitch - barSpacing

    public static func height(level: Float) -> CGFloat {
        minHeight + (maxHeight - minHeight) * loudness(level)
    }

    public static func scrollOffset(time: Double) -> CGFloat {
        let progress = time / secondsPerBar
        return -CGFloat(progress - progress.rounded(.down)) * pitch
    }

    public static func sampleTime(slot: Int, time: Double) -> Double {
        ((time / secondsPerBar).rounded(.down) - Double(barCount - slot)) * secondsPerBar - latency
    }

    private static func loudness(_ level: Float) -> CGFloat {
        CGFloat(pow(Double(min(max(level, 0), 1)), loudnessExponent))
    }
}
