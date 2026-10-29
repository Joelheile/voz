import AVFoundation
import FluidAudio

enum SpokenWord {
    static let timeout = Duration.seconds(10)

    static func hear(_ word: String, transcriber: Transcriber, settings: AppSettings) async -> String? {
        let model = await settings.localSpeechModel
        guard await transcriber.isReady(model) else { return nil }
        do {
            let samples = try await withTimeout(timeout, onTimeout: CleanupError.timedOut) { try await speak(word) }
            return try await transcriber.transcribe(samples, model: model, vocabulary: []).text
        } catch {
            Log.app.error("Vocabulary speech check failed: \(error.localizedDescription, privacy: .private)")
            return nil
        }
    }

    @MainActor
    private static func speak(_ word: String) async throws -> [Float] {
        let synthesizer = AVSpeechSynthesizer()
        let converter = AudioConverter()
        var samples: [Float] = []
        var finished = false
        return try await withCheckedThrowingContinuation { continuation in
            synthesizer.write(AVSpeechUtterance(string: word)) { buffer in
                guard !finished, let buffer = buffer as? AVAudioPCMBuffer else { return }
                do {
                    if buffer.frameLength > 0 {
                        samples += try converter.resampleBuffer(buffer)
                        return
                    }
                    finished = true
                    withExtendedLifetime(synthesizer) { continuation.resume(returning: samples) }
                } catch {
                    finished = true
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
