import CoreAudio
import Foundation
import Synchronization

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
    /// The microphone delivers every 100 ms or so, even in silence, so a longer gap means it stopped
    static let stalled = Duration.seconds(4)
    private static let watchEvery = Duration.seconds(1)

    /// When the microphone last delivered audio
    final class Heartbeat: Sendable {
        private let last = Mutex(ContinuousClock.now)

        func beat() { last.withLock { $0 = .now } }
        var silentFor: Duration { ContinuousClock.now - last.withLock { $0 } }
    }

    private final class Latest: Sendable {
        let value = Mutex((you: LiveTranscript.make([], seconds: 0), call: LiveTranscript.make([], seconds: 0)))
    }

    private final class Session {
        let activity: String
        let makeCapture: () -> LiveCapture
        let inputs: [AsyncStream<[Float]>.Continuation]
        let heartbeat: Heartbeat
        var capture: LiveCapture
        var restarted = ContinuousClock.now
        var result: Task<FileTranscript, any Error>!
        var watch: Task<Void, Never>?
        var outputListener: AudioObjectPropertyListenerBlock?

        init(activity: String, inputs: [AsyncStream<[Float]>.Continuation], heartbeat: Heartbeat, makeCapture: @escaping () -> LiveCapture) {
            self.activity = activity
            self.inputs = inputs
            self.heartbeat = heartbeat
            self.makeCapture = makeCapture
            capture = makeCapture()
        }

        /// Starts a new capture on the current devices, such as after AirPods connect or the microphone goes away
        func restart(because reason: String) {
            Log.extensions.notice("Restarting live capture: \(reason, privacy: .public)")
            capture.stop()
            capture = makeCapture()
            restarted = .now
            do {
                try capture.start()
            } catch {
                Log.extensions.error("Live capture restart failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        func endRecording() {
            watch?.cancel()
            watch = nil
            if let outputListener {
                var address = LiveSessions.defaultOutputAddress
                AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, outputListener)
            }
            outputListener = nil
            capture.stop()
            for input in inputs { input.finish() }
        }
    }

    private let transcriber: Transcriber
    private let vocabulary: VocabularyStore?
    private let settings: AppSettings
    private var sessions: [String: Session] = [:]
    let status = LiveStatus()

    var isEmpty: Bool { sessions.isEmpty }

    init(transcriber: Transcriber, vocabulary: VocabularyStore?, settings: AppSettings) {
        self.transcriber = transcriber
        self.vocabulary = vocabulary
        self.settings = settings
    }

    func start(_ params: LiveStartParams, onTranscript deliver: @escaping @Sendable (FileTranscript) async -> Void) async throws {
        let status = status
        let onTranscript: @Sendable (FileTranscript) async -> Void = { transcript in
            await MainActor.run { status.hear(transcript.text) }
            await deliver(transcript)
        }
        let separate = params.systemAudio && params.you == true
        let session: Session
        if separate {
            session = try await startSeparate(params, onTranscript: onTranscript)
        } else {
            let live = LiveTranscriber(transcriber: transcriber, model: settings.localSpeechModel, vocabulary: vocabulary, onTranscript: onTranscript)
            try await live.prepare(speakers: params.speakers)
            let (stream, input) = AsyncStream.makeStream(of: [Float].self)
            session = makeSession(params, inputs: [input], separate: false) { _, samples in input.yield(samples) }
            session.result = Self.run(live, on: stream, session: session, status: status)
        }
        do {
            try session.capture.start()
        } catch {
            session.endRecording()
            session.result.cancel()
            throw error
        }
        watch(session, systemAudio: params.systemAudio)
        sessions[params.session] = session
        status.begin()
    }

    func stop(_ id: String) async throws -> FileTranscript {
        guard let session = sessions.removeValue(forKey: id) else { throw LiveSessionError.unknown(id) }
        session.endRecording()
        status.end()
        return try await session.result.value
    }

    /// Keeps the session so `stop()` still returns what was said before the activity ended
    func endActivity(_ activity: String) {
        for session in sessions.values where session.activity == activity { session.endRecording() }
        status.end()
    }

    func stopAll() {
        for session in sessions.values {
            session.endRecording()
            session.result.cancel()
        }
        sessions = [:]
        status.end()
    }

    /// Transcribes the microphone and the call apart, so the user's turns are marked and the speakers' echo drops out
    private func startSeparate(
        _ params: LiveStartParams, onTranscript: @escaping @Sendable (FileTranscript) async -> Void
    ) async throws -> Session {
        let echo = LiveEcho()
        let latest = Latest()
        let model = settings.localSpeechModel
        let mine = LiveTranscriber(transcriber: transcriber, model: model, vocabulary: vocabulary, role: .microphone(echo)) { transcript in
            await onTranscript(latest.value.withLock { $0.you = transcript; return LiveTranscript.combine(you: $0.you, call: $0.call) })
        }
        let call = LiveTranscriber(transcriber: transcriber, model: model, vocabulary: vocabulary, role: .system(echo)) { transcript in
            await onTranscript(latest.value.withLock { $0.call = transcript; return LiveTranscript.combine(you: $0.you, call: $0.call) })
        }
        try await mine.prepare(speakers: false)
        try await call.prepare(speakers: params.speakers)
        let (micStream, micInput) = AsyncStream.makeStream(of: [Float].self)
        let (systemStream, systemInput) = AsyncStream.makeStream(of: [Float].self)
        let session = makeSession(params, inputs: [micInput, systemInput], separate: true) { source, samples in
            if source == .system { systemInput.yield(samples) } else { micInput.yield(samples) }
        }
        let micResult = Self.run(mine, on: micStream, session: session, status: status)
        let systemResult = Self.run(call, on: systemStream, session: session, status: status)
        session.result = Task {
            async let you = micResult.value
            async let others = systemResult.value
            return try await LiveTranscript.combine(you: you, call: others)
        }
        return session
    }

    private func makeSession(_ params: LiveStartParams, inputs: [AsyncStream<[Float]>.Continuation], separate: Bool, deliver: @escaping @Sendable (LiveSource, [Float]) -> Void) -> Session {
        let preferred = settings.microphone
        let heartbeat = Heartbeat()
        let level = status.level
        return Session(activity: params.activity, inputs: inputs, heartbeat: heartbeat) {
            let microphone = InputDevice.connected(uid: preferred) ?? InputDevice.builtInIfDefaultIsBluetooth()
            return LiveCapture(microphone: microphone, systemAudio: params.systemAudio, separate: separate) { source, samples in
                if source != .system { heartbeat.beat() }
                level.record(samples, fromCall: source == .system)
                deliver(source, samples)
            }
        }
    }

    private static func run(_ live: LiveTranscriber, on stream: AsyncStream<[Float]>, session: Session, status: LiveStatus) -> Task<FileTranscript, any Error> {
        Task {
            do {
                for await samples in stream { try await live.append(samples) }
                return try await live.finish()
            } catch {
                await MainActor.run {
                    session.endRecording()
                    status.stalled = true
                }
                Log.extensions.error("Live transcription failed: \(error.localizedDescription, privacy: .public)")
                throw error
            }
        }
    }

    /// Restarts the capture when the microphone stops delivering or the Mac switches its speakers. Stays stalled until audio comes back.
    private func watch(_ session: Session, systemAudio: Bool) {
        session.watch = Task { @MainActor [weak session, status] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.watchEvery)
                guard let session, !Task.isCancelled else { return }
                let silentFor = session.heartbeat.silentFor
                let stalled = silentFor > Self.stalled
                if status.stalled != stalled { status.stalled = stalled }
                if stalled, ContinuousClock.now - session.restarted > Self.stalled {
                    session.restart(because: "no microphone audio for \(silentFor)")
                }
            }
        }
        guard systemAudio else { return }
        let listener: AudioObjectPropertyListenerBlock = { [weak session] _, _ in
            MainActor.assumeIsolated { session?.restart(because: "the output device changed") }
        }
        var address = Self.defaultOutputAddress
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener) == noErr {
            session.outputListener = listener
        }
    }

    nonisolated static var defaultOutputAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }
}
