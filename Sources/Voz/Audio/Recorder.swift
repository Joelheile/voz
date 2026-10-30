@preconcurrency import AVFoundation
import AudioToolbox
import Synchronization

final class SampleBuffer: Sendable {
    private struct State {
        var samples: [Float] = []
        var onSamples: (@Sendable ([Float]) -> Void)?
    }

    private let state = Mutex(State())

    func begin(onSamples: (@Sendable ([Float]) -> Void)?) {
        state.withLock { $0 = State(onSamples: onSamples) }
    }

    func append(_ chunk: [Float]) {
        let onSamples = state.withLock { state in
            state.samples.append(contentsOf: chunk)
            return state.onSamples
        }
        onSamples?(chunk)
    }

    func end() -> [Float] {
        state.withLock { state in
            defer { state = State() }
            return state.samples
        }
    }
}

final class Resampler: @unchecked Sendable {
    private var converter: AVAudioConverter?
    private let targetFormat: AVAudioFormat
    private var output: AVAudioPCMBuffer?

    init(to targetFormat: AVAudioFormat) {
        self.targetFormat = targetFormat
    }

    func convert(_ input: AVAudioPCMBuffer) -> [Float]? {
        if converter?.inputFormat != input.format {
            converter = AVAudioConverter(from: input.format, to: targetFormat)
        }
        guard let converter else {
            Log.app.error("No converter from \(input.format.description, privacy: .public)")
            return nil
        }
        let ratio = targetFormat.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 32
        if output.map({ $0.frameCapacity < capacity }) ?? true {
            output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity)
        }
        guard let output else { return nil }
        output.frameLength = 0
        nonisolated(unsafe) var inputConsumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if inputConsumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            inputConsumed = true
            inputStatus.pointee = .haveData
            return input
        }
        guard status != .error, let channel = output.floatChannelData?[0] else {
            Log.app.error("Sample conversion failed: \(error?.localizedDescription ?? "unknown", privacy: .private)")
            return nil
        }
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }
}

@MainActor
final class Recorder {
    private struct Capture {
        let engine: AVAudioEngine
        let device: AudioDeviceID?
        let format: AVAudioFormat
    }

    private nonisolated static let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: RecordingFilter.sampleRate,
        channels: 1,
        interleaved: false
    )!

    private var capture: Capture?
    private let buffer = SampleBuffer()
    private var configurationObserver: NSObjectProtocol?
    private let preferredInput: @MainActor () -> String

    private(set) var isRecording = false
    let level = LiveLevel()
    var onSamples: (@Sendable ([Float]) -> Void)?
    var onInterrupted: (@MainActor () -> Void)?

    /// `preferredInput` returns the UID of the mic to record from, or an empty string for the system default.
    init(preferredInput: @escaping @MainActor () -> String = { "" }) {
        self.preferredInput = preferredInput
        // The engine posts this on its own queue and waits for observers. Releasing an engine also waits
        // for that queue, so observing on the main queue deadlocks. Hop to the main actor without waiting.
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            let engine = (notification.object as AnyObject?).map(ObjectIdentifier.init)
            Task { @MainActor in self?.configurationChanged(engine: engine) }
        }
    }

    func prepare() {
        guard !isRecording else { return }
        if let stale = capture, !isCurrent(stale) { discard() }
        guard capture == nil else { return }
        do {
            capture = try makeCapture()
        } catch {
            Log.app.error("Recorder prepare failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    func start() throws {
        if let stale = capture, !isCurrent(stale) { discard() }
        let prepared = capture
        capture = nil
        level.store(0)
        buffer.begin(onSamples: onSamples)
        do {
            capture = try Self.startCapture(prepared: prepared, fresh: makeCapture, start: Self.startEngine)
        } catch {
            _ = buffer.end()
            throw error
        }
        isRecording = true
    }

    /// A prepared engine can refuse to start after sleep or a device switch without posting a configuration change.
    static func startCapture<C>(prepared: C?, fresh: () throws -> C, start: (C) throws -> Void) throws -> C {
        if let prepared {
            do {
                try start(prepared)
                return prepared
            } catch {
                let code = (error as NSError).code
                Log.app.notice("Prepared engine refused to start (\(code, privacy: .public)), using a fresh one")
            }
        }
        let capture = try fresh()
        try start(capture)
        return capture
    }

    func stop() -> [Float] {
        capture?.engine.stop()
        isRecording = false
        return buffer.end()
    }

    private func configurationChanged(engine: ObjectIdentifier?) {
        guard let capture, ObjectIdentifier(capture.engine) == engine else { return }
        if isRecording {
            rebuildWhileRecording()
        } else {
            discard()
            prepare()
        }
    }

    private func isCurrent(_ capture: Capture) -> Bool {
        capture.device == selectedInput() && capture.engine.inputNode.outputFormat(forBus: 0) == capture.format
    }

    private func discard() {
        if let capture { Self.tearDown(capture) }
        capture = nil
    }

    private static func startEngine(_ capture: Capture) throws {
        do {
            try capture.engine.start()
        } catch {
            tearDown(capture)
            throw error
        }
    }

    private static func tearDown(_ capture: Capture) {
        capture.engine.inputNode.removeTap(onBus: 0)
        capture.engine.stop()
    }

    private func makeCapture() throws -> Capture {
        let engine = AVAudioEngine()
        let chosen = InputDevice.connected(uid: preferredInput())
        let device = chosen ?? InputDevice.defaultInput()
        if let override = chosen ?? InputDevice.builtInIfDefaultIsBluetooth() {
            use(override, on: engine)
        }
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.channelCount > 0, inputFormat.sampleRate > 0 else {
            throw RecorderError.inputUnavailable
        }
        let resampler = Resampler(to: Self.targetFormat)
        let buffer = buffer
        // A nil format follows the hardware. Passing a format read moments earlier raises an uncatchable
        // exception when the device changes in between.
        input.installTap(onBus: 0, bufferSize: 1024, format: nil) { @Sendable pcm, _ in
            guard let converted = resampler.convert(pcm) else { return }
            buffer.append(converted)
        }
        let meter = Self.makeMeter(storingInto: level)
        engine.attach(meter)
        engine.connect(input, to: meter, format: nil)
        engine.prepare()
        return Capture(engine: engine, device: device, format: inputFormat)
    }

    private nonisolated static func makeMeter(storingInto level: LiveLevel) -> AVAudioSinkNode {
        AVAudioSinkNode { @Sendable _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: audioBufferList))
            let samples = buffers.first?.mData?.assumingMemoryBound(to: Float.self)
            level.store(AudioLevel.rms(samples, count: Int(frameCount)))
            return noErr
        }
    }

    private func rebuildWhileRecording() {
        Log.app.notice("Audio configuration changed, rebuilding engine")
        discard()
        level.store(0)
        do {
            let capture = try makeCapture()
            try capture.engine.start()
            self.capture = capture
        } catch {
            Log.app.error("Engine rebuild failed: \(error.localizedDescription, privacy: .private)")
            onInterrupted?()
        }
    }

    private func selectedInput() -> AudioDeviceID? {
        InputDevice.connected(uid: preferredInput()) ?? InputDevice.defaultInput()
    }

    private func use(_ device: AudioDeviceID, on engine: AVAudioEngine) {
        guard let unit = engine.inputNode.audioUnit else { return }
        var device = device
        let status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &device,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if status != noErr {
            Log.app.error("Selecting mic failed: \(status)")
        }
    }
}

enum RecorderError: Error {
    case inputUnavailable
}

final class LiveLevel: Sendable {
    private let bits = Atomic<UInt32>(0)

    var rms: Float { Float(bitPattern: bits.load(ordering: .relaxed)) }

    func store(_ rms: Float) {
        bits.store(rms.bitPattern, ordering: .relaxed)
    }
}
