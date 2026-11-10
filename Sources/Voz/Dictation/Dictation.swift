import AppKit

struct Recording {
    let samples: [Float]
    let app: HostApp
    let trigger: DictationTrigger
    /// False for `voz dictation stop --print`: the text goes to history and the terminal, not into the front app
    var inserts = true
    /// Quick send: the app in front when you asked to send. Voz presses Return after inserting while it is still in front
    var sendTarget: pid_t?
}

@MainActor
final class Dictation {
    typealias Phase = DictationPhase

    enum Outcome {
        case done
        case discarded
        case failed
    }

    private let recorder: Recorder
    private let muter = OutputMuter()
    private let pipeline: DictationPipeline
    private let settings: AppSettings
    private let analytics: Analytics
    private var recordingApp: Task<HostApp, Never>?
    private var recordingTrigger = DictationTrigger.tap
    private var recordingInserts = true
    private var recordingSendTarget: pid_t?
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
        recorder = Recorder { settings.microphone }
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

    /// Stops, inserts the text and presses Return once it is in, so a chat message goes out in one step
    func stopAndSend() {
        guard phase == .recording else { return }
        recordingSendTarget = NSWorkspace.shared.frontmostApplication?.processIdentifier
        stopAfterTrailingWords()
    }

    /// Throws the recording away without transcribing it
    func cancel() {
        guard phase == .recording, let session = streaming else { return }
        _ = recorder.stop()
        muter.unmute()
        streaming = nil
        session.cancel()
        Log.app.notice("Recording canceled")
        onOutcome(.discarded)
        phase = .idle
    }

    /// Stops without typing the text anywhere, so `voz dictation stop --print` can print it
    func stopWithoutInserting() {
        guard phase == .recording else { return }
        recordingInserts = false
        stopAfterTrailingWords()
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
        let app = HostApp.front()
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
            analytics.capture(.dictationFailed(stage: .recording, errorCode: .recorderStartFailed, status: (error as NSError).code))
            onStartFailed("Could not start recording. Check your microphone.")
            return
        }
        streaming = session
        let cuePlayed = settings.soundCues && SoundCues.play(.start)
        recordingApp = app
        recordingTrigger = trigger
        recordingInserts = true
        recordingSendTarget = nil
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

    /// Keeps recording briefly after release to catch the last word, and stops early once the speaker is already quiet
    private func stopAfterTrailingWords() {
        let released = ContinuousClock.now
        phase = .transcribing
        Task {
            while ContinuousClock.now - released < .milliseconds(300), (streaming?.trailingSilence ?? .zero) < .milliseconds(150) {
                try? await Task.sleep(for: .milliseconds(20))
            }
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
            transcribe(samples, app: recordingApp, trigger: recordingTrigger, inserts: recordingInserts, sendTarget: recordingSendTarget, streaming: session, released: released)
        }
    }

    private func discard(_ session: StreamingDictation, reason: DiscardReason) {
        session.cancel()
        Log.app.notice("Recording discarded: \(reason.rawValue, privacy: .public)")
        analytics.capture(.dictationDiscarded(reason: reason))
        onOutcome(.discarded)
        phase = .idle
    }

    private func transcribe(_ samples: [Float], app: Task<HostApp, Never>?, trigger: DictationTrigger, inserts: Bool, sendTarget: pid_t?, streaming: StreamingDictation, released: ContinuousClock.Instant) {
        phase = .transcribing
        Task {
            defer { phase = .idle }
            let recording = Recording(samples: samples, app: await app?.value ?? HostApp(bundleID: nil, name: nil), trigger: trigger, inserts: inserts, sendTarget: sendTarget)
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
