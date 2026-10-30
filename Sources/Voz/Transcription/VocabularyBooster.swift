import FluidAudio
import Foundation

actor VocabularyBooster {
    static let minimumSimilarity: Float = 0.6

    private struct Prepared {
        let terms: [VocabularyTerm]
        let vocabulary: CustomVocabularyContext
        let spotter: CtcKeywordSpotter
        let rescorer: VocabularyRescorer
        let sizeConfig: ContextBiasingConstants.VocabSizeConfig
    }

    private var prepared: Prepared?

    func prepare(terms: [VocabularyTerm]) async throws {
        guard !terms.isEmpty else {
            prepared = nil
            return
        }
        if prepared?.terms == terms { return }
        let started = Date()
        let ctcModels = try await CtcModels.downloadAndLoad()
        let context = CustomVocabularyContext(terms: terms.map {
            CustomVocabularyTerm(text: $0.word, aliases: $0.aliases.isEmpty ? nil : $0.aliases)
        })
        let tokenized = try await VocabularyBoostingSession(vocabulary: context, ctcModels: ctcModels).vocabulary
        let spotter = CtcKeywordSpotter(models: ctcModels, blankId: ctcModels.vocabulary.count)
        let rescorer = try await VocabularyRescorer.create(
            spotter: spotter,
            vocabulary: tokenized,
            ctcModelDirectory: CtcModels.defaultCacheDirectory(for: ctcModels.variant)
        )
        prepared = Prepared(
            terms: terms,
            vocabulary: tokenized,
            spotter: spotter,
            rescorer: rescorer,
            sizeConfig: ContextBiasingConstants.rescorerConfig(forVocabSize: tokenized.terms.count)
        )
        Log.app.notice("Vocabulary boosting ready with \(terms.count) words in \(Date().timeIntervalSince(started), format: .fixed(precision: 1))s")
    }

    func rescore(_ result: ASRResult, samples: [Float], words: [String]) async -> String {
        guard !words.isEmpty else { return result.text }
        guard let prepared, prepared.terms.map(\.word) == words else {
            Log.app.notice("Vocabulary boosting not ready, transcribing without it")
            return result.text
        }
        guard let tokenTimings = result.tokenTimings, !tokenTimings.isEmpty else {
            Log.app.error("Vocabulary boosting skipped, transcription has no token timings")
            return result.text
        }
        do {
            let spotted = try await prepared.spotter.spotKeywordsWithLogProbs(
                audioSamples: samples,
                customVocabulary: prepared.vocabulary,
                minScore: nil
            )
            let evidence = prepared.rescorer.ctcTokenEvaluateCandidates(
                transcript: result.text,
                tokenTimings: tokenTimings,
                logProbs: spotted.logProbs,
                frameDuration: spotted.frameDuration,
                cbw: prepared.sizeConfig.cbw,
                marginSeconds: 0.5,
                minSimilarity: prepared.sizeConfig.minSimilarity
            )
            let edits = evidence.candidates.compactMap(Self.edit)
            return TextSplice.apply(edits, to: result.text)
        } catch {
            Log.app.error("Vocabulary boosting failed: \(error.localizedDescription, privacy: .private)")
            return result.text
        }
    }

    private static func edit(_ candidate: VocabularyRescorer.CandidateEvidence) -> TextEdit? {
        guard
            candidate.legacyOutcome == .applied,
            candidate.similarity >= minimumSimilarity,
            let range = candidate.baseTextUTF8Range
        else { return nil }
        return TextEdit(utf8Range: range, replacement: candidate.canonicalTerm)
    }
}
