import Accelerate
import Foundation

enum AudioLevel {
    static let floorDecibels: Float = -50
    static let ceilingDecibels: Float = -10

    static func rms(of samples: [Float]) -> Float {
        samples.withUnsafeBufferPointer { rms($0.baseAddress, count: $0.count) }
    }

    static func rms(_ samples: UnsafePointer<Float>?, count: Int) -> Float {
        guard let samples, count > 0 else { return 0 }
        var result: Float = 0
        vDSP_rmsqv(samples, 1, &result, vDSP_Length(count))
        return result
    }

    static func normalized(rms: Float) -> Float {
        guard rms > 0 else { return 0 }
        let decibels = 20 * log10(rms)
        let fraction = (decibels - floorDecibels) / (ceilingDecibels - floorDecibels)
        return min(max(fraction, 0), 1)
    }
}

struct LevelSmoother {
    private static let attackSeconds = 0.02
    private static let releaseSeconds = 0.08
    private(set) var value: Float = 0

    init() {}

    mutating func update(target: Float, elapsedSeconds: Double) -> Float {
        let timeConstant = target > value ? Self.attackSeconds : Self.releaseSeconds
        let weight = Float(1 - exp(-max(elapsedSeconds, 0) / timeConstant))
        value += (target - value) * weight
        return value
    }
}

struct LevelHistory: Sendable {
    static let capacity = 256

    private struct Sample: Sendable {
        let time: Double
        let level: Float
    }

    private var samples: [Sample] = []

    init() {}

    var latest: Float { samples.last?.level ?? 0 }

    mutating func append(_ level: Float, at time: Double) {
        samples.append(Sample(time: time, level: level))
        if samples.count > Self.capacity { samples.removeFirst(samples.count - Self.capacity) }
    }

    mutating func reset() {
        samples.removeAll(keepingCapacity: true)
    }

    func level(at time: Double) -> Float {
        guard let first = samples.first, time >= first.time else { return 0 }
        guard let after = samples.firstIndex(where: { $0.time > time }) else { return latest }
        let older = samples[after - 1]
        let newer = samples[after]
        let fraction = Float((time - older.time) / (newer.time - older.time))
        return older.level + (newer.level - older.level) * fraction
    }

    func average(in window: ClosedRange<Double>) -> Float {
        let levels = samples.filter { window.contains($0.time) }.map(\.level)
        guard !levels.isEmpty else { return level(at: window.upperBound) }
        return levels.reduce(0, +) / Float(levels.count)
    }
}

struct PauseDetector: Sendable {
    static let frameSamples = 320
    static let pauseSeconds = 0.6
    static let relaxedPauseSeconds = 0.25
    static let relaxedAfterSeconds = 20.0
    static let minimumSegmentSeconds = 2.0
    static let minimumSpeechSeconds = 0.4
    static let noiseFloorMultiplier: Float = 4
    static let absoluteThreshold: Float = 0.002
    static let maximumNoiseFloor: Float = 0.006
    static let noiseWindowFrames = 150

    private var pending: [Float] = []
    private var processedSamples = 0
    private var segmentStart = 0
    private var speechFrames = 0
    private var silentFrames = 0
    private var recentLevels: [Float] = []

    init() {}

    mutating func append(_ samples: [Float]) -> [Int] {
        pending.append(contentsOf: samples)
        var cuts: [Int] = []
        var offset = 0
        while pending.count - offset >= Self.frameSamples {
            let frame = Array(pending[offset..<offset + Self.frameSamples])
            offset += Self.frameSamples
            processedSamples += Self.frameSamples
            if consume(rms: AudioLevel.rms(of: frame)) {
                cuts.append(processedSamples)
                segmentStart = processedSamples
                speechFrames = 0
                silentFrames = 0
            }
        }
        pending.removeFirst(offset)
        return cuts
    }

    private mutating func consume(rms: Float) -> Bool {
        let floor = updatedNoiseFloor(rms)
        if rms >= max(floor * Self.noiseFloorMultiplier, Self.absoluteThreshold) {
            speechFrames += 1
            silentFrames = 0
            return false
        }
        silentFrames += 1
        let segmentSeconds = Self.seconds(processedSamples - segmentStart)
        let requiredSilence = segmentSeconds >= Self.relaxedAfterSeconds ? Self.relaxedPauseSeconds : Self.pauseSeconds
        return Self.seconds(silentFrames * Self.frameSamples) >= requiredSilence
            && segmentSeconds >= Self.minimumSegmentSeconds
            && Self.seconds(speechFrames * Self.frameSamples) >= Self.minimumSpeechSeconds
    }

    private mutating func updatedNoiseFloor(_ rms: Float) -> Float {
        recentLevels.append(rms)
        if recentLevels.count > Self.noiseWindowFrames { recentLevels.removeFirst() }
        return min(recentLevels.min() ?? rms, Self.maximumNoiseFloor)
    }

    private static func seconds(_ samples: Int) -> Double {
        Double(samples) / RecordingFilter.sampleRate
    }
}

enum RecordingVerdict: Equatable, Sendable {
    case keep
    case tooShort
    case silent
}

enum RecordingFilter {
    static let sampleRate: Double = 16_000
    static let minimumDuration: TimeInterval = 0.3
    static let silenceRMSThreshold: Float = 0.003

    static func verdict(for samples: [Float]) -> RecordingVerdict {
        guard Double(samples.count) / sampleRate >= minimumDuration else { return .tooShort }
        return AudioLevel.rms(of: samples) < silenceRMSThreshold ? .silent : .keep
    }
}

enum WAVEncoder {
    static func encode(_ samples: [Float], sampleRate: Int) -> Data {
        let bytesPerSample = 2
        let dataSize = samples.count * bytesPerSample
        var data = Data(capacity: 44 + dataSize)
        data.append(contentsOf: Array("RIFF".utf8))
        data.append(littleEndian: UInt32(36 + dataSize))
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        data.append(littleEndian: UInt32(16))
        data.append(littleEndian: UInt16(1))
        data.append(littleEndian: UInt16(1))
        data.append(littleEndian: UInt32(sampleRate))
        data.append(littleEndian: UInt32(sampleRate * bytesPerSample))
        data.append(littleEndian: UInt16(bytesPerSample))
        data.append(littleEndian: UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        data.append(littleEndian: UInt32(dataSize))
        for sample in samples {
            data.append(littleEndian: Int16(max(-1, min(1, sample)) * Float(Int16.max)))
        }
        return data
    }
}

private extension Data {
    mutating func append<Value: FixedWidthInteger>(littleEndian value: Value) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
