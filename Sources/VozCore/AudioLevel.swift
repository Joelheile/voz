import Accelerate

public enum AudioLevel {
    public static let floorDecibels: Float = -50
    public static let ceilingDecibels: Float = -10

    public static func rms(of samples: [Float]) -> Float {
        samples.withUnsafeBufferPointer { rms($0.baseAddress, count: $0.count) }
    }

    public static func rms(_ samples: UnsafePointer<Float>?, count: Int) -> Float {
        guard let samples, count > 0 else { return 0 }
        var result: Float = 0
        vDSP_rmsqv(samples, 1, &result, vDSP_Length(count))
        return result
    }

    public static func normalized(rms: Float) -> Float {
        guard rms > 0 else { return 0 }
        let decibels = 20 * log10(rms)
        let fraction = (decibels - floorDecibels) / (ceilingDecibels - floorDecibels)
        return min(max(fraction, 0), 1)
    }
}

public struct LevelSmoother {
    private static let attackSeconds = 0.02
    private static let releaseSeconds = 0.08
    public private(set) var value: Float = 0

    public init() {}

    public mutating func update(target: Float, elapsedSeconds: Double) -> Float {
        let timeConstant = target > value ? Self.attackSeconds : Self.releaseSeconds
        let weight = Float(1 - exp(-max(elapsedSeconds, 0) / timeConstant))
        value += (target - value) * weight
        return value
    }
}
