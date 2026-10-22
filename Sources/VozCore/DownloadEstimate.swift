import Foundation

public enum DownloadEstimate {
    private static let minimumFraction = 0.02
    private static let minimumElapsed: TimeInterval = 2

    public static func detail(fraction: Double, elapsed: TimeInterval) -> String {
        let percent = "\(Int(fraction * 100))%"
        guard let remaining = remaining(fraction: fraction, elapsed: elapsed) else { return percent }
        return "\(percent), \(describe(remaining))"
    }

    private static func remaining(fraction: Double, elapsed: TimeInterval) -> TimeInterval? {
        guard fraction >= minimumFraction, fraction < 1, elapsed >= minimumElapsed else { return nil }
        return elapsed * (1 - fraction) / fraction
    }

    private static func describe(_ seconds: TimeInterval) -> String {
        guard seconds >= 60 else { return "under a minute left" }
        return "\(Int((seconds / 60).rounded())) min left"
    }
}
