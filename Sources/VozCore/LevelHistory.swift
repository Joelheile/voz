public struct LevelHistory: Sendable {
    public static let capacity = 256

    private struct Sample: Sendable {
        let time: Double
        let level: Float
    }

    private var samples: [Sample] = []

    public init() {}

    public var latest: Float { samples.last?.level ?? 0 }

    public mutating func append(_ level: Float, at time: Double) {
        samples.append(Sample(time: time, level: level))
        if samples.count > Self.capacity { samples.removeFirst(samples.count - Self.capacity) }
    }

    public mutating func reset() {
        samples.removeAll(keepingCapacity: true)
    }

    public func level(at time: Double) -> Float {
        guard let first = samples.first, time >= first.time else { return 0 }
        guard let after = samples.firstIndex(where: { $0.time > time }) else { return latest }
        let older = samples[after - 1]
        let newer = samples[after]
        let fraction = Float((time - older.time) / (newer.time - older.time))
        return older.level + (newer.level - older.level) * fraction
    }

    public func average(in window: ClosedRange<Double>) -> Float {
        let levels = samples.filter { window.contains($0.time) }.map(\.level)
        guard !levels.isEmpty else { return level(at: window.upperBound) }
        return levels.reduce(0, +) / Float(levels.count)
    }
}
