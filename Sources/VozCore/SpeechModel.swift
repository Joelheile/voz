public enum SpeechModel: String, CaseIterable, Sendable {
    case parakeetUltra = "parakeet-ultra"
    case parakeetRedux = "parakeet-redux"
    case parakeetV2 = "parakeet-tdt-v2"
    case appleSpeech = "apple-speech"

    public var label: String {
        switch self {
        case .parakeetUltra: "Ultra, most accurate, 630 MB"
        case .parakeetRedux: "Redux, smallest, 220 MB"
        case .parakeetV2: "English only, 500 MB"
        case .appleSpeech: "Apple, built in, no download"
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
