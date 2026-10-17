import Foundation
import VozCore

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

@MainActor
final class TextCleaner {
    static let minimumWordsForModel = 4

    private let model: LanguageModelCleaner
    private let budget: Duration

    init(examples: [CleanupExample] = CleanupExamples.all, budget: Duration = CleanupBudget.total) {
        model = LanguageModelCleaner(examples: examples)
        self.budget = budget
    }

    func prewarm(vocabulary: [String]) {
        if let reason = model.availabilityDescription {
            Log.app.notice("Cleanup model unavailable, rule pass only: \(reason)")
            return
        }
        model.prewarm(vocabulary: vocabulary)
    }

    func ruleText(_ raw: String, vocabulary: [String]) -> (text: String, fillersRemoved: Int) {
        let fillers = FillerWords.removeObvious(from: raw)
        return (VocabularyCasing.apply(vocabulary, to: SpokenPunctuation.apply(to: fillers.text)), fillers.removed)
    }

    func clean(_ raw: String, vocabulary: [String], deadline: ContinuousClock.Instant? = nil) async -> CleanedText {
        let started = ContinuousClock.now
        let deadline = deadline ?? started + budget
        let rules = ruleText(raw, vocabulary: vocabulary)
        let chunks = SentenceChunks.split(rules.text)

        var finished: [ChunkResult] = []
        if let reason = model.availabilityDescription {
            Log.app.notice("Cleanup skipped, model unavailable: \(reason)")
            finished = chunks.map { ChunkResult(text: $0, removed: 0, timedOut: false, rejection: nil) }
        } else {
            for chunk in chunks {
                finished.append(await cleanChunk(chunk, vocabulary: vocabulary, deadline: deadline))
            }
        }
        let elapsed = ContinuousClock.now - started
        prewarm(vocabulary: vocabulary)
        return CleanedText(
            text: finished.map(\.text).joined(),
            fillerWordsRemoved: rules.fillersRemoved + finished.reduce(0) { $0 + $1.removed },
            milliseconds: elapsed.wholeMilliseconds,
            timedOut: finished.contains { $0.timedOut },
            rejection: finished.compactMap(\.rejection).first
        )
    }

    private func cleanChunk(_ chunk: String, vocabulary: [String], deadline: ContinuousClock.Instant) async -> ChunkResult {
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
            let modelOutput = try await model.clean(chunk, vocabulary: vocabulary, wordCount: wordCount, timeout: remaining)
            let output = CleanupOutput.sanitized(modelOutput, raw: chunk)
            if let rejection = CleanupGuard.rejection(raw: chunk, cleaned: output) {
                Log.app.notice("Cleanup output rejected (\(rejection.rawValue)), using rule-pass text")
                return ChunkResult(text: chunk, removed: 0, timedOut: false, rejection: rejection)
            }
            let finalText = VocabularyCasing.apply(vocabulary, to: output)
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
            return ChunkResult(text: chunk, removed: 0, timedOut: true, rejection: nil)
        }
    }
}
