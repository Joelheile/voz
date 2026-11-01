import Foundation

enum LiveSessionError: LocalizedError {
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .unknown(let session): "No live transcription \(session)"
        }
    }
}

/// Live transcriptions that extensions run inside their activities. Ending the activity stops the recording at once.
@MainActor
final class LiveSessions {
    private struct Session {
        let activity: String
        let capture: LiveCapture
        let input: AsyncStream<[Float]>.Continuation
        let result: Task<FileTranscript, any Error>

        func endRecording() {
            capture.stop()
            input.finish()
        }
    }

    private let transcriber: Transcriber
    private let vocabulary: VocabularyStore?
    private let settings: AppSettings
    private var sessions: [String: Session] = [:]

    var isEmpty: Bool { sessions.isEmpty }

    init(transcriber: Transcriber, vocabulary: VocabularyStore?, settings: AppSettings) {
        self.transcriber = transcriber
        self.vocabulary = vocabulary
        self.settings = settings
    }

    func start(_ params: LiveStartParams, onTranscript: @escaping @Sendable (FileTranscript) async -> Void) async throws {
        let live = LiveTranscriber(transcriber: transcriber, model: settings.localSpeechModel, vocabulary: vocabulary, onTranscript: onTranscript)
        try await live.prepare(speakers: params.speakers)
        let (stream, input) = AsyncStream.makeStream(of: [Float].self)
        let microphone = InputDevice.connected(uid: settings.microphone) ?? InputDevice.builtInIfDefaultIsBluetooth()
        let capture = LiveCapture(microphone: microphone, systemAudio: params.systemAudio) { input.yield($0) }
        let result = Task {
            do {
                for await samples in stream { try await live.append(samples) }
                return try await live.finish()
            } catch {
                capture.stop()
                input.finish()
                Log.extensions.error("Live transcription failed: \(error.localizedDescription, privacy: .public)")
                throw error
            }
        }
        let session = Session(activity: params.activity, capture: capture, input: input, result: result)
        do {
            try capture.start()
        } catch {
            session.endRecording()
            result.cancel()
            throw error
        }
        sessions[params.session] = session
    }

    func stop(_ id: String) async throws -> FileTranscript {
        guard let session = sessions.removeValue(forKey: id) else { throw LiveSessionError.unknown(id) }
        session.endRecording()
        return try await session.result.value
    }

    /// Keeps the session so `stop()` still returns what was said before the activity ended
    func endActivity(_ activity: String) {
        for session in sessions.values where session.activity == activity { session.endRecording() }
    }

    func stopAll() {
        for session in sessions.values {
            session.endRecording()
            session.result.cancel()
        }
        sessions = [:]
    }
}
