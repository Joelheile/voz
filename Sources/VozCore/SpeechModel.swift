public enum SpeechModel: String, CaseIterable, Sendable {
    case parakeetUltra = "parakeet-ultra"
    case parakeetEnglish = "parakeet-english-v2"
    case appleSpeech = "apple-speech"

    public var name: String {
        switch self {
        case .parakeetUltra: "Ultra"
        case .parakeetEnglish: "English v2"
        case .appleSpeech: "Apple"
        }
    }

    public var family: String {
        switch self {
        case .parakeetUltra, .parakeetEnglish: "Parakeet"
        case .appleSpeech: "macOS"
        }
    }

    public var languages: String {
        switch self {
        case .parakeetUltra: "25 languages"
        case .parakeetEnglish: "English"
        case .appleSpeech: "2 languages"
        }
    }

    public var errorRate: Double {
        switch self {
        case .parakeetUltra: 3.8
        case .parakeetEnglish: 3.2
        case .appleSpeech: 4.6
        }
    }

    public var speedFactor: Int {
        switch self {
        case .parakeetUltra: 127
        case .parakeetEnglish: 146
        case .appleSpeech: 70
        }
    }

    public var size: String {
        switch self {
        case .parakeetUltra: "630 MB"
        case .parakeetEnglish: "480 MB"
        case .appleSpeech: "Built in"
        }
    }
}
