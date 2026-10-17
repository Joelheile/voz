import Accelerate

public enum AudioLevel {
    public static let floorDecibels: Float = -50
    public static let ceilingDecibels: Float = -10

    public static func rms(of samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var result: Float = 0
        vDSP_rmsqv(samples, 1, &result, vDSP_Length(samples.count))
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
    public let attackSeconds: Double
    public let releaseSeconds: Double
    public private(set) var value: Float = 0

    public init(attackSeconds: Double = 0.04, releaseSeconds: Double = 0.18) {
        self.attackSeconds = attackSeconds
        self.releaseSeconds = releaseSeconds
    }

    public mutating func update(target: Float, elapsedSeconds: Double) -> Float {
        let timeConstant = target > value ? attackSeconds : releaseSeconds
        let weight = Float(1 - exp(-max(elapsedSeconds, 0) / timeConstant))
        value += (target - value) * weight
        return value
    }
}
