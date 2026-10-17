import FluidAudio
import Foundation
import VozCore

final class SpeechEngine: Sendable {
    private let parakeet: Transcriber
    private let apple = AppleSpeechTranscriber()
    private let forceApple: Bool

    init(parakeet: Transcriber, forceApple: Bool = false) {
        self.parakeet = parakeet
        self.forceApple = forceApple
    }

    func transcribe(_ samples: [Float], mode: LanguageMode, vocabulary: [String]) async throws -> TranscriptionResult {
        if await usesParakeet(mode) {
            return try await parakeet.transcribe(samples, mode: mode, vocabulary: vocabulary)
        }
        Log.app.notice("Parakeet not ready, using Apple speech")
        return try await apple.transcribe(samples, locale: Self.locale(for: mode), vocabulary: vocabulary)
    }

    func transcribeFile(_ url: URL, mode: LanguageMode, vocabulary: [String]) async throws -> TranscriptionResult {
        if await usesParakeet(mode) {
            return try await parakeet.transcribeFile(url, mode: mode, vocabulary: vocabulary)
        }
        let samples = try AudioConverter().resampleAudioFile(url)
        return try await apple.transcribe(samples, locale: Self.locale(for: mode), vocabulary: vocabulary)
    }

    private func usesParakeet(_ mode: LanguageMode) async -> Bool {
        guard !forceApple else { return false }
        return await parakeet.isReady(mode)
    }

    static func locale(for mode: LanguageMode) -> Locale {
        switch mode {
        case .english: Locale(identifier: "en_US")
        case .automatic: Locale.current.language.languageCode == "de" ? Locale(identifier: "de_DE") : Locale(identifier: "en_US")
        }
    }
}
