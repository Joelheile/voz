import AppKit
import VozCore

struct FrontApp {
    let bundleID: String?
    let name: String?

    @MainActor
    static var current: FrontApp {
        let app = NSWorkspace.shared.frontmostApplication
        return FrontApp(bundleID: app?.bundleIdentifier, name: app?.localizedName)
    }
}

struct LastRecording {
    let samples: [Float]
    let app: FrontApp
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
    private var recordingApp = FrontApp(bundleID: nil, name: nil)
    private var recordingTrigger = DictationTrigger.tap
    private var lastRecording: LastRecording?
    private var streaming: StreamingDictation?
    private let activity = ActivityHold()

    private(set) var phase = Phase.idle {
        didSet {
            activity.set(held: phase != .idle)
            onChange()
        }
    }
    var hasLastRecording: Bool { lastRecording != nil }
    var isRecording: Bool { phase == .recording }

    var onChange: () -> Void = {}
    var onOutcome: (Outcome) -> Void = { _ in }
    var onLevel: (Float) -> Void = { _ in }
    var onBusy: () -> Void = {}

    init(pipeline: DictationPipeline, settings: AppSettings, output: TextOutput, analytics: Analytics) {
        self.pipeline = pipeline
        self.settings = settings
        self.output = output
        self.analytics = analytics
        recorder.onLevel = { [weak self] level in self?.onLevel(level) }
        recorder.onInterrupted = { [weak self] in self?.stopIfRecording() }
    }

    func prepareRecorder() {
        guard Permissions.microphoneGranted else { return }
        recorder.prepare()
    }

    func recoverFromPreviousRun() {
        muter.restoreLeftoverMute()
    }

    func handle(_ action: HotkeyAction) {
        switch DictationCommand.command(for: action, in: phase) {
        case let .start(trigger): start(trigger: trigger)
        case .stop: stopAndTranscribe()
        case .rejectBusy: onBusy()
        case .ignore: break
        }
    }

    func stopIfRecording() {
        guard phase == .recording else { return }
        Log.app.notice("Recording interrupted, transcribing what was captured")
        stopAndTranscribe()
    }

    func retryLast() {
        guard phase == .idle, let lastRecording else { return }
        analytics.capture(.retryUsed)
        transcribe(lastRecording, streaming: nil)
    }

    func copy(_ text: String) {
        output.copy(text)
    }

    private func start(trigger: DictationTrigger) {
        pipeline.collectLearnedWords()
        guard Permissions.microphoneGranted else {
            Log.app.error("Microphone access not granted")
            analytics.capture(.dictationFailed(stage: .recording, errorCode: .microphoneDenied))
            Task { await Permissions.requestMicrophone() }
            return
        }
        let session = pipeline.makeStreaming()
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
        let cuePlayed = SoundCues.play(.start)
        recordingApp = FrontApp.current
        recordingTrigger = trigger
        phase = .recording
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
        let session = streaming
        streaming = nil
        muter.unmuteIfMutedByVoz()
        SoundCues.play(.stop)
        switch RecordingFilter.verdict(for: samples) {
        case .tooShort:
            session?.cancel()
            Log.app.notice("Recording discarded: too short")
            analytics.capture(.dictationDiscarded(reason: .tooShort))
            onOutcome(.discarded)
            phase = .idle
        case .silent:
            session?.cancel()
            Log.app.notice("Recording discarded: silent")
            analytics.capture(.dictationDiscarded(reason: .silent))
            onOutcome(.discarded)
            phase = .idle
        case .keep:
            let recording = LastRecording(samples: samples, app: recordingApp, trigger: recordingTrigger)
            lastRecording = recording
            transcribe(recording, streaming: session, released: released)
        }
    }

    private func transcribe(_ recording: LastRecording, streaming: StreamingDictation?, released: ContinuousClock.Instant = .now) {
        phase = .transcribing
        Task {
            defer { phase = .idle }
            onOutcome(await pipeline.run(recording, streaming: streaming, released: released))
        }
    }
}
