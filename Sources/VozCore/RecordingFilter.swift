import Foundation

public enum RecordingVerdict: Equatable, Sendable {
    case keep
    case tooShort
    case silent
}

public enum RecordingFilter {
    public static let sampleRate: Double = 16_000
    public static let minimumDuration: TimeInterval = 0.3
    public static let silenceRMSThreshold: Float = 0.003

    public static func verdict(for samples: [Float]) -> RecordingVerdict {
        guard Double(samples.count) / sampleRate >= minimumDuration else { return .tooShort }
        return AudioLevel.rms(of: samples) < silenceRMSThreshold ? .silent : .keep
    }
}
