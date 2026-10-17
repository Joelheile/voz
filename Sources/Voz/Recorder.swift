@preconcurrency import AVFoundation
import AudioToolbox
import VozCore

final class SampleBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []

    func append(_ chunk: [Float]) {
        lock.withLock { samples.append(contentsOf: chunk) }
    }

    func takeAll() -> [Float] {
        lock.withLock {
            let taken = samples
            samples = []
            return taken
        }
    }
}

@MainActor
final class Recorder {
    private nonisolated static let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: RecordingFilter.sampleRate,
        channels: 1,
        interleaved: false
    )!

    private var engine: AVAudioEngine?
    private let buffer = SampleBuffer()
    private var configurationObserver: NSObjectProtocol?

    var isRecording: Bool { engine != nil }
    var onLevel: (@MainActor (Float) -> Void)?
    var onSamples: (@Sendable ([Float]) -> Void)?
    var onInterrupted: (@MainActor () -> Void)?

    func start() throws {
        _ = buffer.takeAll()
        try startEngine()
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildEngine() }
        }
    }

    func stop() -> [Float] {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
        configurationObserver = nil
        tearDownEngine()
        return buffer.takeAll()
    }

    private func startEngine() throws {
        let engine = AVAudioEngine()
        selectBuiltInMicIfDefaultIsBluetooth(engine)
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: inputFormat, to: Self.targetFormat) else {
            throw RecorderError.converterUnavailable
        }
        let buffer = buffer
        let onSamples = onSamples
        let levelTap = LevelTap { [weak self] level in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.onLevel?(level) } }
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { pcm, _ in
            guard let converted = Recorder.convert(pcm, with: converter) else { return }
            buffer.append(converted)
            levelTap.process(converted)
            onSamples?(converted)
        }
        engine.prepare()
        try engine.start()
        self.engine = engine
    }

    private func tearDownEngine() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
    }

    private func rebuildEngine() {
        guard engine != nil else { return }
        Log.app.notice("Audio configuration changed, rebuilding engine")
        tearDownEngine()
        do {
            try startEngine()
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

    private nonisolated static func convert(_ input: AVAudioPCMBuffer, with converter: AVAudioConverter) -> [Float]? {
        let ratio = targetFormat.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return nil }
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

enum RecorderError: Error {
    case converterUnavailable
}
