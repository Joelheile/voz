import Foundation

enum SpeechModel: String, CaseIterable, Sendable {
    case parakeetUltra = "parakeet-ultra"
    case parakeetEnglish = "parakeet-english-v2"
    case appleSpeech = "apple-speech"

    var name: String {
        switch self {
        case .parakeetUltra: "Ultra"
        case .parakeetEnglish: "English v2"
        case .appleSpeech: "Apple"
        }
    }

    var family: String {
        switch self {
        case .parakeetUltra, .parakeetEnglish: "Parakeet"
        case .appleSpeech: "macOS"
        }
    }

    var languages: String {
        switch self {
        case .parakeetUltra: "25 languages"
        case .parakeetEnglish: "English"
        case .appleSpeech: "2 languages"
        }
    }

    var errorRate: Double {
        switch self {
        case .parakeetUltra: 3.8
        case .parakeetEnglish: 3.2
        case .appleSpeech: 4.6
        }
    }

    var speedFactor: Int {
        switch self {
        case .parakeetUltra: 127
        case .parakeetEnglish: 146
        case .appleSpeech: 70
        }
    }

    var size: String {
        switch self {
        case .parakeetUltra: "630 MB"
        case .parakeetEnglish: "480 MB"
        case .appleSpeech: "Built in"
        }
    }

    static func analyticsLabel(for id: String) -> String {
        SpeechModel(rawValue: id)?.rawValue ?? "extension"
    }
}

enum DownloadEstimate {
    private static let minimumFraction = 0.02
    private static let minimumElapsed: TimeInterval = 2

    static func detail(fraction: Double, elapsed: TimeInterval) -> String {
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
