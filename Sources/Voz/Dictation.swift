import AppKit
import VozCore

extension HostApp {
    @MainActor
    static var current: HostApp {
        let app = NSWorkspace.shared.frontmostApplication
        return HostApp(bundleID: app?.bundleIdentifier, name: app?.localizedName)
    }
}

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
    private let output: TextOutput
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

    init(pipeline: DictationPipeline, settings: AppSettings, output: TextOutput, analytics: Analytics) {
        self.pipeline = pipeline
        self.settings = settings
        self.output = output
        self.analytics = analytics
        recorder.onInterrupted = { [weak self] in self?.stopIfRecording() }
    }

    func prepareRecorder() {
        guard Permissions.microphoneGranted else { return }
        recorder.prepare()
    }

    func handle(_ action: HotkeyAction) {
        switch (action, phase) {
        case (.toggle, .idle): start(trigger: .tap)
        case (.start, .idle): start(trigger: .hold)
        case (.toggle, .recording), (.stop, .recording): stopAndTranscribe()
        case (.toggle, .transcribing), (.start, .transcribing): onBusy()
        default: break
        }
    }

    func stopIfRecording() {
        guard phase == .recording else { return }
        Log.app.notice("Recording interrupted, transcribing what was captured")
        stopAndTranscribe()
    }

    func copy(_ text: String) {
        output.copy(text)
    }

    private func start(trigger: DictationTrigger) {
        guard Permissions.microphoneGranted else {
            Log.app.error("Microphone access not granted")
            analytics.capture(.dictationFailed(stage: .recording, errorCode: .microphoneDenied))
            Task { await Permissions.requestMicrophone() }
            return
        }
        let app = HostApp.current
        let session = pipeline.makeStreaming(app: app)
        recorder.onSamples = { chunk in
            DispatchQueue.main.async { MainActor.assumeIsolated { session.feed(chunk) } }
        }
        let startClock = ContinuousClock.now
        do {
            try recorder.start()
            Log.app.notice("Recorder started in \((ContinuousClock.now - startClock).wholeMilliseconds) ms")
        } catch {
            session.cancel()
            Log.app.error("Recording failed to start: \(error.localizedDescription, privacy: .private)")
            analytics.capture(.dictationFailed(stage: .recording, errorCode: .recorderStartFailed))
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

    private func stopAndTranscribe() {
        let released = ContinuousClock.now
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
        case .tooShort:
            session.cancel()
            Log.app.notice("Recording discarded: too short")
            analytics.capture(.dictationDiscarded(reason: .tooShort))
            onOutcome(.discarded)
            phase = .idle
        case .silent:
            session.cancel()
            Log.app.notice("Recording discarded: silent")
            analytics.capture(.dictationDiscarded(reason: .silent))
            onOutcome(.discarded)
            phase = .idle
        case .keep:
            let recording = Recording(samples: samples, app: recordingApp, trigger: recordingTrigger)
            transcribe(recording, streaming: session, released: released)
        }
    }

    private func transcribe(_ recording: Recording, streaming: StreamingDictation, released: ContinuousClock.Instant) {
        phase = .transcribing
        Task {
            defer { phase = .idle }
            onOutcome(await pipeline.run(recording, streaming: streaming, released: released))
        }
    }
}
