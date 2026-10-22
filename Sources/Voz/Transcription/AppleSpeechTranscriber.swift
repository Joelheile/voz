@preconcurrency import AVFoundation
import Foundation
import Speech

enum AppleSpeechError: Error {
    case localeUnsupported(String)
    case audioFormatUnavailable
    case conversionFailed
}

actor AppleSpeechTranscriber {
    func transcribe(_ samples: [Float], locale: Locale, vocabulary: [String]) async throws -> TranscriptionResult {
        let started = Date()
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw AppleSpeechError.localeUnsupported(locale.identifier)
        }
        let transcriber = SpeechTranscriber(locale: supported, preset: .transcription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            Log.app.notice("Installing Apple speech assets for \(supported.identifier)")
            try await request.downloadAndInstall()
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw AppleSpeechError.audioFormatUnavailable
        }
        let buffer = try Self.buffer(from: samples, format: format)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        if !vocabulary.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = vocabulary
            try await analyzer.setContext(context)
        }
        let (inputs, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        try await analyzer.start(inputSequence: inputs)
        continuation.yield(AnalyzerInput(buffer: buffer))
        continuation.finish()
        async let transcript = Self.collect(transcriber.results)
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        let text = try await transcript
        return TranscriptionResult(
            text: text,
            audioSeconds: Double(samples.count) / RecordingFilter.sampleRate,
            processingSeconds: Date().timeIntervalSince(started),
            model: SpeechModel.appleSpeech.rawValue
        )
    }

    private static func collect(_ results: some AsyncSequence<SpeechTranscriber.Result, any Error>) async throws -> String {
        var text = ""
        for try await result in results {
            text += String(result.text.characters)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func buffer(from samples: [Float], format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        guard
            let sourceFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: RecordingFilter.sampleRate, channels: 1, interleaved: false),
            let source = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(samples.count)),
            let converter = AVAudioConverter(from: sourceFormat, to: format)
        else { throw AppleSpeechError.conversionFailed }
        source.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        let ratio = format.sampleRate / RecordingFilter.sampleRate
        let capacity = AVAudioFrameCount(Double(samples.count) * ratio) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw AppleSpeechError.conversionFailed
        }
        nonisolated(unsafe) var consumed = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .endOfStream
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return source
        }
        guard status != .error, conversionError == nil else { throw AppleSpeechError.conversionFailed }
        return output
    }
}
