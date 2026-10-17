public enum LanguageMode: String, CaseIterable, Sendable {
    case automatic
    case english

    public var modelName: String {
        switch self {
        case .automatic: "parakeet-tdt-v3"
        case .english: "parakeet-tdt-v2"
        }
    }

    public var title: String {
        switch self {
        case .automatic: "Automatic"
        case .english: "English only"
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
