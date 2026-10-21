public enum CleanupStep: String, CaseIterable, Sendable {
    case fillers
    case punctuation
    case dictionary
    case model

    public static let standard = allCases.map(\.rawValue)

    public var name: String {
        switch self {
        case .fillers: "Remove filler words"
        case .punctuation: "Spoken punctuation"
        case .dictionary: "Dictionary spellings"
        case .model: "Cleanup model"
        }
    }

    public static func applyRules(_ steps: [String], to text: String, vocabulary: [String]) -> FillerPassResult {
        var text = text
        var removed = 0
        for step in steps.compactMap(CleanupStep.init) {
            switch step {
            case .fillers:
                let result = FillerWords.removeObvious(from: text)
                text = result.text
                removed += result.removed
            case .punctuation: text = SpokenPunctuation.apply(to: text)
            case .dictionary: text = VocabularyCasing.apply(vocabulary, to: text)
            case .model: break
            }
        }
        return FillerPassResult(text: text, removed: removed)
    }
}

public enum CleanupModelID {
    public static let apple = "apple"
}

public struct PipelineChoices: Equatable, Sendable {
    public var speechModel: String
    public var cleanupModel: String
    public var cleanupSteps: [String]

    public static let standard = PipelineChoices(speechModel: SpeechModel.parakeetUltra.rawValue, cleanupModel: CleanupModelID.apple, cleanupSteps: CleanupStep.standard)

    public init(speechModel: String, cleanupModel: String, cleanupSteps: [String]) {
        self.speechModel = speechModel
        self.cleanupModel = cleanupModel
        self.cleanupSteps = cleanupSteps
    }
}
