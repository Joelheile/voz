public enum SpeechModel: String, CaseIterable, Sendable {
    case parakeetUltra = "parakeet-ultra"
    case parakeetV2 = "parakeet-tdt-v2"
    case appleSpeech = "apple-speech"

    public var name: String {
        switch self {
        case .parakeetUltra: "Ultra"
        case .parakeetV2: "English only"
        case .appleSpeech: "Apple"
        }
    }

    public var size: String {
        switch self {
        case .parakeetUltra: "630 MB"
        case .parakeetV2: "500 MB"
        case .appleSpeech: "No download"
        }
    }
}

extension IndicatorStyle {
    public var title: String {
        switch self {
        case .notch: "Notch"
        case .pill: "Pill"
        }
    }
}
