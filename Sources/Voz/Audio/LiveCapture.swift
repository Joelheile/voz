@preconcurrency import AVFoundation
import CoreAudio
import Synchronization

/// Mixes the microphone with system audio. A source that stops delivering, such as a muted output, can't hold back the other.
struct LiveMix {
    static let maxLag = Int(RecordingFilter.sampleRate / 2)

    private var mic: [Float] = []
    private var system: [Float] = []

    mutating func add(mic samples: [Float]) -> [Float] {
        mic += samples
        return drain()
    }

    mutating func add(system samples: [Float]) -> [Float] {
        system += samples
        return drain()
    }

    private mutating func drain() -> [Float] {
        let count = min(mic.count, system.count)
        var mixed = zip(mic.prefix(count), system.prefix(count)).map(+)
        mic.removeFirst(count)
        system.removeFirst(count)
        if mic.count > Self.maxLag { mixed += mic; mic = [] }
        if system.count > Self.maxLag { mixed += system; system = [] }
        return mixed
    }
}

enum LiveCaptureError: LocalizedError {
    case microphoneUnavailable
    case systemAudio(step: String, status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .microphoneUnavailable: "Voz can't use the microphone"
        case .systemAudio(let step, let status): "Voz can't record system audio: \(step) returned \(status)"
        }
    }
}

/// Records the microphone, and optionally everything the Mac plays, as 16 kHz mono
final class LiveCapture: @unchecked Sendable {
    private static let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: RecordingFilter.sampleRate, channels: 1, interleaved: false)!

    private let microphone: AudioDeviceID?
    private let systemAudio: Bool
    private let onSamples: @Sendable ([Float]) -> Void
    private let mix = Mutex(LiveMix())
    private let engine = AVAudioEngine()
    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var ioProc: AudioDeviceIOProcID?

    init(microphone: AudioDeviceID?, systemAudio: Bool, onSamples: @escaping @Sendable ([Float]) -> Void) {
        self.microphone = microphone
        self.systemAudio = systemAudio
        self.onSamples = onSamples
    }

    func start() throws {
        do {
            try startMicrophone()
            if systemAudio { try startSystemAudio() }
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        if let ioProc {
            AudioDeviceStop(device, ioProc)
            AudioDeviceDestroyIOProcID(device, ioProc)
        }
        ioProc = nil
        if device != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(device) }
        device = AudioObjectID(kAudioObjectUnknown)
        if tap != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tap) }
        tap = AudioObjectID(kAudioObjectUnknown)
    }

    private func startMicrophone() throws {
        if let microphone { Recorder.use(microphone, on: engine) }
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.channelCount > 0, inputFormat.sampleRate > 0 else { throw LiveCaptureError.microphoneUnavailable }
        let resampler = Resampler(to: Self.format)
        input.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] pcm, _ in
            guard let self, let samples = resampler.convert(pcm) else { return }
            deliver(systemAudio ? mix.withLock { $0.add(mic: samples) } : samples)
        }
        try engine.start()
    }

    private func startSystemAudio() throws {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: OutputMuter.ownProcessObject.map { [$0] } ?? [])
        description.muteBehavior = .unmuted
        description.isPrivate = true
        try check(AudioHardwareCreateProcessTap(description, &tap), "create tap")
        let output = try Self.defaultOutputUID()
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Voz live",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: output,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: output]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: description.uuid.uuidString]],
        ]
        try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &device), "create aggregate device")
        var stream = try property(tap, kAudioTapPropertyFormat, AudioStreamBasicDescription())
        guard let tapFormat = AVAudioFormat(streamDescription: &stream) else { throw LiveCaptureError.systemAudio(step: "read tap format", status: kAudioHardwareUnsupportedOperationError) }
        let resampler = Resampler(to: Self.format, downmix: true)
        try check(AudioDeviceCreateIOProcIDWithBlock(&ioProc, device, nil) { [weak self] _, input, _, _, _ in
            guard
                let self,
                let pcm = AVAudioPCMBuffer(pcmFormat: tapFormat, bufferListNoCopy: input, deallocator: nil),
                let samples = resampler.convert(pcm)
            else { return }
            deliver(mix.withLock { $0.add(system: samples) })
        }, "create IO proc")
        try check(AudioDeviceStart(device, ioProc), "start IO")
    }

    private func deliver(_ samples: [Float]) {
        if !samples.isEmpty { onSamples(samples) }
    }

    private static func defaultOutputUID() throws -> String {
        let output = try property(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultSystemOutputDevice, AudioObjectID(kAudioObjectUnknown))
        guard let uid = try property(output, kAudioDevicePropertyDeviceUID, Unmanaged<CFString>?.none) else {
            throw LiveCaptureError.systemAudio(step: "read output device", status: kAudioHardwareBadDeviceError)
        }
        return uid.takeRetainedValue() as String
    }

    private func check(_ status: OSStatus, _ step: String) throws {
        guard status == noErr else { throw LiveCaptureError.systemAudio(step: step, status: status) }
    }
}

private func property<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ initial: T) throws -> T {
    var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var value = initial
    var size = UInt32(MemoryLayout<T>.size)
    let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0) }
    guard status == noErr else { throw LiveCaptureError.systemAudio(step: "read property \(selector)", status: status) }
    return value
}
