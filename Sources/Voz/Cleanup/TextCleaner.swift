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

    private let model = LanguageModelCleaner()
    private let budget: Duration

    init(budget: Duration = CleanupBudget.total) {
        self.budget = budget
    }

    func prewarm(_ setup: CleanupSetup) {
        if let reason = model.availabilityDescription {
            Log.app.notice("Cleanup model unavailable, inserting raw text: \(reason)")
            return
        }
        model.prewarm(setup)
    }

    func clean(
        _ raw: String,
        plan: CleanupPlan,
        vocabulary: [String],
        languages: [SpeechLanguage],
        steps: [String] = CleanupStep.standard,
        extensions: CleanupExtensions = .none,
        deadline: ContinuousClock.Instant? = nil
    ) async -> CleanedText {
        let started = ContinuousClock.now
        let deadline = deadline ?? started + budget
        let setup = CleanupSetup(plan: plan, vocabulary: vocabulary, languages: languages)
        var text = raw
        var modelResults: [ChunkResult] = []
        for step in steps {
            if CleanupStep(rawValue: step) == .model {
                modelResults = await modelPass(text, setup: setup, model: extensions.model, deadline: deadline)
                text = modelResults.map(\.text).joined()
            } else {
                text = await extensions.step(step, text, deadline)
            }
        }
        let elapsed = ContinuousClock.now - started
        if extensions.model == nil { prewarm(setup) }
        return CleanedText(
            text: text,
            fillerWordsRemoved: modelResults.reduce(0) { $0 + $1.removed },
            milliseconds: elapsed.wholeMilliseconds,
            timedOut: modelResults.contains { $0.timedOut },
            rejection: modelResults.compactMap(\.rejection).first
        )
    }

    private func modelPass(_ text: String, setup: CleanupSetup, model extensionModel: CleanupExtensions.Model?, deadline: ContinuousClock.Instant) async -> [ChunkResult] {
        if let extensionModel {
            return [await cleanChunk(text, setup: setup, deadline: deadline) { chunk, _, timeout in
                guard let cleaned = await extensionModel(chunk, setup.instructions, timeout) else { throw CleanupError.extensionFailed }
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
            finished.append(await cleanChunk(chunk, setup: setup, deadline: deadline) { [model] chunk, wordCount, timeout in
                try await model.clean(chunk, setup: setup, wordCount: wordCount, timeout: timeout)
            })
        }
        return finished
    }

    private func cleanChunk(
        _ chunk: String,
        setup: CleanupSetup,
        deadline: ContinuousClock.Instant,
        run: (String, Int, Duration) async throws -> String
    ) async -> ChunkResult {
        let wordCount = chunk.split(whereSeparator: \.isWhitespace).count
        let unchanged = ChunkResult(text: chunk, removed: 0, timedOut: false, rejection: nil)
        guard wordCount >= Self.minimumWordsForModel else { return unchanged }
        let remaining = deadline - ContinuousClock.now
        guard remaining >= CleanupBudget.minimumChunkWindow else {
            Log.app.notice("Cleanup budget too small for chunk, using raw text")
            return ChunkResult(text: chunk, removed: 0, timedOut: true, rejection: nil)
        }
        let trailing = String(chunk.reversed().prefix(while: \.isWhitespace).reversed())
        do {
            let modelOutput = try await run(chunk, wordCount, remaining)
            let output = CleanupOutput.sanitized(modelOutput, raw: chunk)
            if let rejection = CleanupGuard.rejection(raw: chunk, cleaned: output, mode: setup.mode, vocabulary: setup.vocabulary) {
                Log.app.notice("Cleanup output rejected (\(rejection.rawValue)), using raw text")
                return ChunkResult(text: chunk, removed: 0, timedOut: false, rejection: rejection)
            }
            return ChunkResult(
                text: output + trailing,
                removed: FillerWords.estimateRemoved(before: chunk, after: output),
                timedOut: false,
                rejection: nil
            )
        } catch is CancellationError {
            return unchanged
        } catch CleanupError.timedOut {
            Log.app.notice("Cleanup chunk timed out, using raw text")
            return ChunkResult(text: chunk, removed: 0, timedOut: true, rejection: nil)
        } catch {
            Log.app.error("Cleanup chunk failed, using raw text: \(error.localizedDescription, privacy: .private)")
            Analytics.report(.cleanupFailed, cause: error)
            return unchanged
        }
    }
}
