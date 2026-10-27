import Foundation

struct CleanedText: Equatable {
    let text: String
    let fillerWordsRemoved: Int
    let milliseconds: Int
    let timedOut: Bool
    var rejection: CleanupRejection?
}

private struct ChunkResult: Sendable {
    let text: String
    let removed: Int
    let timedOut: Bool
    let rejection: CleanupRejection?
}

struct CleanupExtensions {
    typealias Model = @MainActor (_ text: String, _ prompt: String, _ timeout: Duration) async -> String?

    let model: Model?
    let step: @MainActor (_ id: String, _ text: String, _ deadline: ContinuousClock.Instant) async -> String

    static let none = CleanupExtensions(model: nil) { _, text, _ in text }
}

@MainActor
final class TextCleaner {
    static let minimumWordsForModel = 4

    private let model: LanguageModelCleaner
    private let budget: Duration

    init(budget: Duration = CleanupBudget.total) {
        model = LanguageModelCleaner(examples: CleanupExamples.all)
        self.budget = budget
    }

    func prewarm(prompt: String, vocabulary: [String]) {
        if let reason = model.availabilityDescription {
            Log.app.notice("Cleanup model unavailable, rule pass only: \(reason)")
            return
        }
        model.prewarm(instructions: CleanupInstructions.text(prompt: prompt, vocabulary: vocabulary))
    }

    func clean(
        _ raw: String,
        prompt: String,
        vocabulary: [String],
        steps: [String] = CleanupStep.standard,
        extensions: CleanupExtensions = .none,
        deadline: ContinuousClock.Instant? = nil
    ) async -> CleanedText {
        let started = ContinuousClock.now
        let deadline = deadline ?? started + budget
        let casing = steps.contains(CleanupStep.dictionary.rawValue) ? vocabulary : []
        var text = raw
        var removed = 0
        var modelResults: [ChunkResult] = []
        for step in steps {
            switch CleanupStep(rawValue: step) {
            case .model:
                modelResults = await modelPass(text, prompt: prompt, vocabulary: vocabulary, casing: casing, model: extensions.model, deadline: deadline)
                text = modelResults.map(\.text).joined()
                removed += modelResults.reduce(0) { $0 + $1.removed }
            case .some:
                let rules = CleanupStep.applyRules([step], to: text, vocabulary: vocabulary)
                text = rules.text
                removed += rules.removed
            case nil:
                text = await extensions.step(step, text, deadline)
            }
        }
        let elapsed = ContinuousClock.now - started
        if extensions.model == nil { prewarm(prompt: prompt, vocabulary: vocabulary) }
        return CleanedText(
            text: text,
            fillerWordsRemoved: removed,
            milliseconds: elapsed.wholeMilliseconds,
            timedOut: modelResults.contains { $0.timedOut },
            rejection: modelResults.compactMap(\.rejection).first
        )
    }

    private func modelPass(_ text: String, prompt: String, vocabulary: [String], casing: [String], model extensionModel: CleanupExtensions.Model?, deadline: ContinuousClock.Instant) async -> [ChunkResult] {
        let instructions = CleanupInstructions.text(prompt: prompt, vocabulary: vocabulary)
        if let extensionModel {
            return [await cleanChunk(text, casing: casing, deadline: deadline) { chunk, _, timeout in
                guard let cleaned = await extensionModel(chunk, instructions, timeout) else { throw CleanupError.extensionFailed }
                return cleaned
            }]
        }
        let chunks = SentenceChunks.split(text)
        if let reason = model.availabilityDescription {
            Log.app.notice("Cleanup skipped, model unavailable: \(reason)")
            return chunks.map { ChunkResult(text: $0, removed: 0, timedOut: false, rejection: nil) }
        }
        var finished: [ChunkResult] = []
        for chunk in chunks {
            finished.append(await cleanChunk(chunk, casing: casing, deadline: deadline) { [model] chunk, wordCount, timeout in
                try await model.clean(chunk, instructions: instructions, wordCount: wordCount, timeout: timeout)
            })
        }
        return finished
    }

    private func cleanChunk(
        _ chunk: String,
        casing: [String],
        deadline: ContinuousClock.Instant,
        run: (String, Int, Duration) async throws -> String
    ) async -> ChunkResult {
        let wordCount = chunk.split(whereSeparator: \.isWhitespace).count
        let unchanged = ChunkResult(text: chunk, removed: 0, timedOut: false, rejection: nil)
        guard wordCount >= Self.minimumWordsForModel else { return unchanged }
        let remaining = deadline - ContinuousClock.now
        guard remaining >= CleanupBudget.minimumChunkWindow else {
            Log.app.notice("Cleanup budget too small for chunk, using rule-pass text")
            return ChunkResult(text: chunk, removed: 0, timedOut: true, rejection: nil)
        }
        let trailing = String(chunk.reversed().prefix(while: \.isWhitespace).reversed())
        do {
            let modelOutput = try await run(chunk, wordCount, remaining)
            let output = CleanupOutput.sanitized(modelOutput, raw: chunk)
            if let rejection = CleanupGuard.rejection(raw: chunk, cleaned: output) {
                Log.app.notice("Cleanup output rejected (\(rejection.rawValue)), using rule-pass text")
                return ChunkResult(text: chunk, removed: 0, timedOut: false, rejection: rejection)
            }
            let finalText = VocabularyCasing.apply(casing, to: output)
            return ChunkResult(
                text: finalText + trailing,
                removed: FillerWords.estimateRemoved(before: chunk, after: finalText),
                timedOut: false,
                rejection: nil
            )
        } catch CleanupError.timedOut {
            Log.app.notice("Cleanup chunk timed out, using rule-pass text")
            return ChunkResult(text: chunk, removed: 0, timedOut: true, rejection: nil)
        } catch {
            Log.app.error("Cleanup chunk failed, using rule-pass text: \(error.localizedDescription, privacy: .private)")
            Analytics.report(.cleanupFailed)
            return unchanged
        }
    }
}
