@preconcurrency import AVFoundation
import AudioToolbox
import VozCore

final class SampleBuffer: @unchecked Sendable {
    struct Sink {
        let level: LevelTap
        let onSamples: (@Sendable ([Float]) -> Void)?
    }

    private let lock = NSLock()
    private var samples: [Float] = []
    private var sink: Sink?

    func begin(_ sink: Sink) {
        lock.withLock {
            samples = []
            self.sink = sink
        }
    }

    func append(_ chunk: [Float]) {
        let sink = lock.withLock {
            samples.append(contentsOf: chunk)
            return self.sink
        }
        sink?.level.process(chunk)
        sink?.onSamples?(chunk)
    }

    func end() -> [Float] {
        lock.withLock {
            sink = nil
            let taken = samples
            samples = []
            return taken
        }
    }
}

final class Resampler: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let targetFormat: AVAudioFormat
    private var output: AVAudioPCMBuffer?

    init?(from inputFormat: AVAudioFormat, to targetFormat: AVAudioFormat) {
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else { return nil }
        self.converter = converter
        self.targetFormat = targetFormat
    }

    func convert(_ input: AVAudioPCMBuffer) -> [Float]? {
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

    private(set) var isRecording = false
    var onLevel: (@MainActor (Float) -> Void)?
    var onSamples: (@Sendable ([Float]) -> Void)?
    var onInterrupted: (@MainActor () -> Void)?

    init() {
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.configurationChanged() }
        }
    }

    func prepare() {
        guard !isRecording, capture == nil else { return }
        do {
            capture = try makeCapture()
        } catch {
            Log.app.error("Recorder prepare failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    func start() throws {
        if let stale = capture, !isCurrent(stale) { discard() }
        let capture = try capture ?? makeCapture()
        let onLevel = onLevel
        buffer.begin(SampleBuffer.Sink(
            level: LevelTap { level in
                DispatchQueue.main.async { MainActor.assumeIsolated { onLevel?(level) } }
            },
            onSamples: onSamples
        ))
        do {
            try capture.engine.start()
        } catch {
            _ = buffer.end()
            discard()
            throw error
        }
        self.capture = capture
        isRecording = true
    }

    func stop() -> [Float] {
        capture?.engine.stop()
        isRecording = false
        return buffer.end()
    }

    private func configurationChanged() {
        if isRecording {
            rebuildWhileRecording()
        } else {
            discard()
            prepare()
        }
    }

    private func isCurrent(_ capture: Capture) -> Bool {
        capture.device == InputDevice.defaultInput() && capture.engine.inputNode.outputFormat(forBus: 0) == capture.format
    }

    private func discard() {
        capture?.engine.inputNode.removeTap(onBus: 0)
        capture?.engine.stop()
        capture = nil
    }

    private func makeCapture() throws -> Capture {
        let engine = AVAudioEngine()
        let device = InputDevice.defaultInput()
        selectBuiltInMicIfDefaultIsBluetooth(engine)
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard let resampler = Resampler(from: inputFormat, to: Self.targetFormat) else {
            throw RecorderError.converterUnavailable
        }
        let buffer = buffer
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { @Sendable pcm, _ in
            guard let converted = resampler.convert(pcm) else { return }
            buffer.append(converted)
        }
        engine.prepare()
        return Capture(engine: engine, device: device, format: inputFormat)
    }

    private func rebuildWhileRecording() {
        Log.app.notice("Audio configuration changed, rebuilding engine")
        discard()
        do {
            let capture = try makeCapture()
            try capture.engine.start()
            self.capture = capture
        } catch {
            Log.app.error("Engine rebuild failed: \(error.localizedDescription, privacy: .private)")
            onInterrupted?()
        }
    }

    private func selectBuiltInMicIfDefaultIsBluetooth(_ engine: AVAudioEngine) {
        guard var device = InputDevice.builtInIfDefaultIsBluetooth(), let unit = engine.inputNode.audioUnit else { return }
        let status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &device,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if status != noErr {
            Log.app.error("Selecting built-in mic failed: \(status)")
        }
    }
}

enum RecorderError: Error {
    case converterUnavailable
}
