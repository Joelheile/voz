import FoundationModels
import VozCore

enum CleanupError: Error {
    case modelUnavailable(String)
    case timedOut
}

@MainActor
final class LanguageModelCleaner {
    private let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
    private let examples: [CleanupExample]
    private var instructions = ""
    private var warmSession: LanguageModelSession?

    init(examples: [CleanupExample]) {
        self.examples = examples
    }

    var availabilityDescription: String? {
        switch model.availability {
        case .available: nil
        case let .unavailable(reason): "\(reason)"
        }
    }

    func prewarm(instructions: String) {
        guard availabilityDescription == nil else { return }
        if warmSession != nil, instructions == self.instructions { return }
        self.instructions = instructions
        startWarmSession()
    }

    func clean(_ text: String, instructions: String, wordCount: Int, timeout: Duration) async throws -> String {
        if let reason = availabilityDescription { throw CleanupError.modelUnavailable(reason) }
        if instructions != self.instructions {
            self.instructions = instructions
            warmSession = nil
        }
        let session = warmSession ?? makeSession()
        warmSession = nil
        let options = GenerationOptions(
            sampling: .greedy,
            maximumResponseTokens: CleanupBudget.maxResponseTokens(forWords: wordCount)
        )
        return try await withTimeout(timeout, onTimeout: CleanupError.timedOut) {
            try await session.respond(to: CleanupInstructions.transcriptPrompt(for: text), options: options).content
        }
    }

    private func startWarmSession() {
        let session = makeSession()
        session.prewarm(promptPrefix: Prompt(CleanupInstructions.promptPrefix))
        warmSession = session
    }

    private func makeSession() -> LanguageModelSession {
        LanguageModelSession(model: model, transcript: makeTranscript())
    }

    private func makeTranscript() -> Transcript {
        var entries: [Transcript.Entry] = [
            .instructions(.init(segments: [.text(.init(content: instructions))], toolDefinitions: [])),
        ]
        for example in examples {
            entries.append(.prompt(.init(segments: [.text(.init(content: CleanupInstructions.transcriptPrompt(for: example.input)))])))
            entries.append(.response(.init(assetIDs: [], segments: [.text(.init(content: example.output))])))
        }
        return Transcript(entries: entries)
    }
}
