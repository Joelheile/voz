import Foundation

public struct PauseDetector: Sendable {
    public static let frameSamples = 320
    public static let pauseSeconds = 0.6
    public static let relaxedPauseSeconds = 0.25
    public static let relaxedAfterSeconds = 20.0
    public static let minimumSegmentSeconds = 2.0
    public static let minimumSpeechSeconds = 0.4
    public static let noiseFloorMultiplier: Float = 4
    public static let absoluteThreshold: Float = 0.002
    public static let maximumNoiseFloor: Float = 0.006
    public static let noiseWindowFrames = 150

    private var pending: [Float] = []
    private var processedSamples = 0
    private var segmentStart = 0
    private var speechFrames = 0
    private var silentFrames = 0
    private var recentLevels: [Float] = []

    public init() {}

    public mutating func append(_ samples: [Float]) -> [Int] {
        pending.append(contentsOf: samples)
        var cuts: [Int] = []
        var offset = 0
        while pending.count - offset >= Self.frameSamples {
            let frame = Array(pending[offset..<offset + Self.frameSamples])
            offset += Self.frameSamples
            processedSamples += Self.frameSamples
            if consume(rms: RecordingFilter.rms(of: frame)) {
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
