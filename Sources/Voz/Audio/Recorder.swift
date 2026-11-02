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

    init(preferredInput: @escaping @MainActor () -> String = { "" }) {
        self.preferredInput = preferredInput
    }

    func prepare() {
        guard !isRecording else { return }
        dropStaleCapture()
        guard capture == nil else { return }
        do {
            capture = try makeCapture()
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
            capture = try Self.startCapture(prepared: prepared, fresh: makeCapture) { try $0.start() }
        } catch {
            _ = buffer.end()
            throw error
        }
        isRecording = true
    }

    /// A prepared queue can refuse to start after sleep or a device switch.
    static func startCapture<C>(prepared: C?, fresh: () throws -> C, start: (C) throws -> Void) throws -> C {
        if let prepared {
            do {
                try start(prepared)
                return prepared
            } catch {
                let code = (error as NSError).code
                Log.app.notice("Prepared microphone refused to start (\(code, privacy: .public)), using a fresh one")
            }
        }
        let capture = try fresh()
        try start(capture)
        return capture
    }

    /// A stopped queue isn't reused, so this prepares the next one right away.
    func stop() -> [Float] {
        capture?.stop()
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

    private func makeCapture() throws -> MicrophoneQueue {
        let buffer = buffer, level = level
        return try MicrophoneQueue(device: selectedInput()) { samples in
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
