@preconcurrency import AVFoundation
import AudioToolbox
import CoreAudio
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
    private let downmix: Bool

    init(to targetFormat: AVAudioFormat, downmix: Bool = false) {
        self.targetFormat = targetFormat
        self.downmix = downmix
    }

    func convert(_ input: AVAudioPCMBuffer) -> [Float]? {
        if converter?.inputFormat != input.format {
            converter = AVAudioConverter(from: input.format, to: targetFormat)
            converter?.downmix = downmix
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
    private var capture: MicrophoneQueue?
    private let buffer = SampleBuffer()
    private let preferredInput: @MainActor () -> String

    private(set) var isRecording = false
    let level = LiveLevel()
    var onSamples: (@Sendable ([Float]) -> Void)?
    var onInterrupted: (@MainActor () -> Void)?

    init(preferredInput: @escaping @MainActor () -> String = { "" }) {
        self.preferredInput = preferredInput
    }

    func prepare() {
        guard !isRecording else { return }
        dropStaleCapture()
        guard capture == nil else { return }
        do {
            capture = try MainThreadActivity.during("recorder_prepare") { try makeCapture() }
        } catch {
            Log.app.error("Recorder prepare failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    func start() throws {
        dropStaleCapture()
        let prepared = capture
        capture = nil
        level.store(0)
        buffer.begin(onSamples: onSamples)
        do {
            let systemDefault: (() throws -> MicrophoneQueue)? = selectedInput() == nil ? nil : { try self.makeCapture(device: nil) }
            capture = try MainThreadActivity.during("recorder_start") {
                try Self.startCapture(prepared: prepared, fresh: { try self.makeCapture() }, fallback: systemDefault) { try $0.start() }
            }
        } catch {
            _ = buffer.end()
            throw error
        }
        isRecording = true
    }

    /// A prepared queue can refuse to start after sleep or a device switch. A chosen microphone that refuses outright
    /// falls back to the system default, so the dictation still records.
    static func startCapture<C>(prepared: C?, fresh: () throws -> C, fallback: (() throws -> C)? = nil, start: (C) throws -> Void) throws -> C {
        if let prepared {
            do {
                try start(prepared)
                return prepared
            } catch {
                let code = (error as NSError).code
                Log.app.notice("Prepared microphone refused to start (\(code, privacy: .public)), using a fresh one")
            }
        }
        do {
            let capture = try fresh()
            try start(capture)
            return capture
        } catch {
            guard let fallback else { throw error }
            Log.app.notice("Microphone refused to start (\((error as NSError).code, privacy: .public)), using the system default")
            let capture = try fallback()
            try start(capture)
            return capture
        }
    }

    /// A stopped queue isn't reused, so this prepares the next one right away.
    func stop() -> [Float] {
        MainThreadActivity.during("recorder_stop") { capture?.stop() }
        capture = nil
        isRecording = false
        let samples = buffer.end()
        prepare()
        return samples
    }

    /// Drops a prepared queue whose microphone is no longer the one to record from
    private func dropStaleCapture() {
        if let capture, capture.device != selectedInput() { self.capture = nil }
    }

    /// Keeps recording on the next microphone, else ends the dictation instead of recording silence
    private func microphoneLost(_ device: AudioDeviceID?) {
        guard let capture, capture.device == device else { return }
        self.capture = nil
        guard isRecording else { return }
        Log.app.notice("Microphone went away while recording, switching to the next one")
        level.store(0)
        do {
            let replacement = try makeCapture()
            try replacement.start()
            self.capture = replacement
        } catch {
            Log.app.error("Microphone switch failed: \(error.localizedDescription, privacy: .private)")
            onInterrupted?()
        }
    }

    private func makeCapture() throws -> MicrophoneQueue {
        try makeCapture(device: selectedInput())
    }

    private func makeCapture(device: AudioDeviceID?) throws -> MicrophoneQueue {
        let buffer = buffer, level = level
        return try MicrophoneQueue(device: device, onDeviceLost: { [weak self] in
            Task { @MainActor in self?.microphoneLost(device) }
        }) { samples in
            level.store(AudioLevel.rms(of: samples))
            buffer.append(samples)
        }
    }

    private func selectedInput() -> AudioDeviceID? {
        InputDevice.forRecording(uid: preferredInput())
    }
}

final class LiveLevel: Sendable {
    private let bits = Atomic<UInt32>(0)

    var rms: Float { Float(bitPattern: bits.load(ordering: .relaxed)) }

    func store(_ rms: Float) {
        bits.store(rms.bitPattern, ordering: .relaxed)
    }
}
