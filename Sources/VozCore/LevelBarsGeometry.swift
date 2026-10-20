import CoreGraphics

public enum LevelBarsGeometry {
    public static let barCount = 5
    public static let barWidth: CGFloat = 3
    public static let barSpacing: CGFloat = 3
    public static let minHeight: CGFloat = 3
    public static let maxHeight: CGFloat = 14
    public static let breathingLevel: CGFloat = 0.18
    public static let waveSpeed = 8.0
    public static let wavePhasePerBar = 0.4
    public static let loudnessExponent = 0.7
    public static let edgeAttenuation: CGFloat = 0.4

    public static func height(level: Float, time: Double, index: Int) -> CGFloat {
        let wave = 0.5 + 0.5 * sin(time * waveSpeed + Double(index) * wavePhasePerBar)
        let speech = loudness(level)
        return minHeight + (maxHeight - minHeight) * max(speech, breathingLevel) * CGFloat(wave) * centerFactor(index)
    }

    public static func staticHeight(level: Float, index: Int) -> CGFloat {
        minHeight + (maxHeight - minHeight) * loudness(level) * centerFactor(index)
    }

    private static func loudness(_ level: Float) -> CGFloat {
        CGFloat(pow(Double(min(max(level, 0), 1)), loudnessExponent))
    }

    private static func centerFactor(_ index: Int) -> CGFloat {
        let middle = CGFloat(barCount - 1) / 2
        return 1 - edgeAttenuation * abs(CGFloat(index) - middle) / middle
    }
}
