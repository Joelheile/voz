import FluidAudio
import Foundation
import VozCore

final class SpeechEngine: Sendable {
    private let parakeet: Transcriber
    private let apple = AppleSpeechTranscriber()

    init(parakeet: Transcriber) {
        self.parakeet = parakeet
    }

    func transcribe(_ samples: [Float], model: SpeechModel, vocabulary: [String]) async throws -> TranscriptionResult {
        if await parakeet.isReady(model) {
            return try await parakeet.transcribe(samples, model: model, vocabulary: vocabulary)
        }
        if model != .appleSpeech { Log.app.notice("Parakeet not ready, using Apple speech") }
        return try await apple.transcribe(samples, locale: Self.locale, vocabulary: vocabulary)
    }

    func transcribeFile(_ url: URL, model: SpeechModel, vocabulary: [String]) async throws -> TranscriptionResult {
        let samples = try AudioConverter().resampleAudioFile(url)
        return try await transcribe(samples, model: model, vocabulary: vocabulary)
    }

    static var locale: Locale {
        Locale.current.language.languageCode == "de" ? Locale(identifier: "de_DE") : Locale(identifier: "en_US")
    }
}
