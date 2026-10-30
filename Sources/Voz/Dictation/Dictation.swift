import Foundation

struct Recording {
    let samples: [Float]
    let app: HostApp
    let trigger: DictationTrigger
}

@MainActor
final class Dictation {
    typealias Phase = DictationPhase

    enum Outcome {
        case done
        case discarded
        case failed
    }

    private let recorder = Recorder()
    private let muter = OutputMuter()
    private let pipeline: DictationPipeline
    private let settings: AppSettings
    private let analytics: Analytics
    private var recordingApp = HostApp(bundleID: nil, name: nil)
    private var recordingTrigger = DictationTrigger.tap
    private var streaming: StreamingDictation?
    private let activity = ActivityHold()

    private(set) var phase = Phase.idle {
        didSet {
            activity.set(held: phase != .idle)
            onChange()
        }
    }
    var isRecording: Bool { phase == .recording }
    var inputLevel: Float { AudioLevel.normalized(rms: recorder.level.rms) }

    var onChange: () -> Void = {}
    var onOutcome: (Outcome) -> Void = { _ in }
    var onBusy: () -> Void = {}
    var onStartFailed: (String) -> Void = { _ in }
    var onPreview: (String) -> Void = { _ in }

    init(pipeline: DictationPipeline, settings: AppSettings, analytics: Analytics) {
        self.pipeline = pipeline
        self.settings = settings
        self.analytics = analytics
        recorder.onInterrupted = { [weak self] in
            analytics.capture(.dictationFailed(stage: .recording, errorCode: .recorderInterrupted))
            self?.stopIfRecording()
        }
    }

    func prepareRecorder() {
        guard Permissions.microphoneGranted else { return }
        recorder.prepare()
    }

    func handle(_ action: HotkeyAction) {
        switch (action, phase) {
        case (.toggle, .idle): start(trigger: .tap)
        case (.start, .idle): start(trigger: .hold)
        case (.toggle, .recording), (.stop, .recording): stopAfterTrailingWords()
        case (.toggle, .transcribing), (.start, .transcribing): onBusy()
        default: break
        }
    }

    func stopIfRecording() {
        guard phase == .recording else { return }
        Log.app.notice("Recording interrupted, transcribing what was captured")
        stopAndTranscribe()
    }

    private func start(trigger: DictationTrigger) {
        guard Permissions.microphoneGranted else {
            Log.app.error("Microphone access not granted")
            analytics.capture(.dictationFailed(stage: .recording, errorCode: .microphoneDenied))
            if !Permissions.microphoneUndecided { onStartFailed("Allow microphone access for Voz in System Settings") }
            Task { await Permissions.requestMicrophone() }
            return
        }
        let app = HostApp.current
        let session = pipeline.makeStreaming(app: app)
        if settings.livePreviewEnabled {
            session.onPreview = { [weak self] text in self?.onPreview(text) }
        }
        recorder.onSamples = { chunk in
            DispatchQueue.main.async { MainActor.assumeIsolated { session.feed(chunk) } }
        }
        let startClock = ContinuousClock.now
        do {
            try recorder.start()
            Log.app.notice("Recorder started in \((ContinuousClock.now - startClock).wholeMilliseconds) ms")
        } catch {
            session.cancel()
            Log.app.error("Recording failed to start (\((error as NSError).code, privacy: .public)): \(error.localizedDescription, privacy: .private)")
            analytics.capture(.dictationFailed(stage: .recording, errorCode: .recorderStartFailed))
            onStartFailed("Could not start recording. Check your microphone.")
            return
        }
        streaming = session
        let cuePlayed = settings.soundCues && SoundCues.play(.start)
        recordingApp = app
        recordingTrigger = trigger
        phase = .recording
        pipeline.collectLearnedWords()
        if settings.muteWhileRecording { mute(after: cuePlayed ? .milliseconds(150) : .zero) }
    }

    private func mute(after delay: Duration) {
        guard delay > .zero else { return muter.mute() }
        Task {
            try await Task.sleep(for: delay)
            guard phase == .recording else { return }
            muter.mute()
        }
    }

    private func stopAfterTrailingWords() {
        let released = ContinuousClock.now
        phase = .transcribing
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            stopAndTranscribe(released: released)
        }
    }

    private func stopAndTranscribe(released: ContinuousClock.Instant = .now) {
        let samples = recorder.stop()
        muter.unmute()
        if settings.soundCues { SoundCues.play(.stop) }
        guard let session = streaming else {
            Log.app.error("Recording stopped without a streaming session")
            phase = .idle
            return
        }
        streaming = nil
        switch RecordingFilter.verdict(for: samples) {
        case .tooShort: discard(session, reason: .tooShort)
        case .silent: discard(session, reason: .silent)
        case .keep:
            let recording = Recording(samples: samples, app: recordingApp, trigger: recordingTrigger)
            transcribe(recording, streaming: session, released: released)
        }
    }

    private func discard(_ session: StreamingDictation, reason: DiscardReason) {
        session.cancel()
        Log.app.notice("Recording discarded: \(reason.rawValue, privacy: .public)")
        analytics.capture(.dictationDiscarded(reason: reason))
        onOutcome(.discarded)
        phase = .idle
    }

    private func transcribe(_ recording: Recording, streaming: StreamingDictation, released: ContinuousClock.Instant) {
        phase = .transcribing
        Task {
            defer { phase = .idle }
            onOutcome(await pipeline.run(recording, streaming: streaming, released: released))
        }
    }
}

@MainActor
final class ActivityHold {
    private var token: NSObjectProtocol?

    func set(held: Bool) {
        switch (held, token) {
        case (true, nil):
            token = ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: "voz dictation")
        case (false, let token?):
            ProcessInfo.processInfo.endActivity(token)
            self.token = nil
        default:
            break
        }
    }
}
