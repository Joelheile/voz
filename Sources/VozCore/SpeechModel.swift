public enum SpeechModel: String, CaseIterable, Sendable {
    case parakeetV3 = "parakeet-tdt-v3"
    case appleSpeech = "apple-speech"

    public var name: String {
        switch self {
        case .parakeetV3: "Parakeet"
        case .appleSpeech: "Apple"
        }
    }

    public var size: String {
        switch self {
        case .parakeetV3: "480 MB"
        case .appleSpeech: "No download"
        }
    }
}
