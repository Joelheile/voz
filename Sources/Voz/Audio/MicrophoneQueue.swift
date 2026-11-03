@preconcurrency import AudioToolbox
import CoreAudio
import Foundation

struct MicrophoneError: LocalizedError {
    let step: String
    let status: OSStatus

    var errorDescription: String? { "Voz can't use the microphone: \(step) returned \(status)" }
}

/// Records one microphone as 16 kHz mono. AVAudioEngine ties the microphone to the output device and refuses to start
/// (-10868) when their sample rates differ, such as the Mac's microphone while Bluetooth headphones play music.
/// An audio queue reads the input alone and converts the rate itself.
final class MicrophoneQueue: @unchecked Sendable {
    private static let bufferFrames: UInt32 = 512
    private static let bufferCount = 4

    /// Nil follows the system default input
    let device: AudioDeviceID?
    private let queue: AudioQueueRef
    private let callbacks: DispatchQueue
    private let deviceListener: AudioObjectPropertyListenerBlock?

    /// The queue stops delivering without an error when its device goes away, so `onDeviceLost` reports that
    init(
        device: AudioDeviceID?,
        onDeviceLost: (@Sendable () -> Void)? = nil,
        onSamples: @escaping @Sendable ([Float]) -> Void
    ) throws {
        var format = AudioStreamBasicDescription(
            mSampleRate: RecordingFilter.sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        var created: AudioQueueRef?
        let callbacks = DispatchQueue(label: "com.joelheile.voz.microphone", qos: .userInteractive)
        try Self.check(AudioQueueNewInputWithDispatchQueue(&created, &format, 0, callbacks) { queue, buffer, _, _, _ in
            let count = Int(buffer.pointee.mAudioDataByteSize) / MemoryLayout<Float>.size
            if count > 0 {
                let samples = buffer.pointee.mAudioData.assumingMemoryBound(to: Float.self)
                onSamples(Array(UnsafeBufferPointer(start: samples, count: count)))
            }
            AudioQueueEnqueueBuffer(queue, buffer, 0, nil)
        }, "create queue")
        guard let created else { throw MicrophoneError(step: "create queue", status: kAudioQueueErr_InvalidQueueType) }
        do {
            if let device { try Self.use(device, on: created) }
            for _ in 0..<Self.bufferCount {
                var buffer: AudioQueueBufferRef?
                try Self.check(AudioQueueAllocateBuffer(created, Self.bufferFrames * format.mBytesPerFrame, &buffer), "allocate buffer")
                if let buffer { try Self.check(AudioQueueEnqueueBuffer(created, buffer, 0, nil), "enqueue buffer") }
            }
        } catch {
            AudioQueueDispose(created, true)
            throw error
        }
        self.device = device
        queue = created
        self.callbacks = callbacks
        if let device, let onDeviceLost {
            let listener: AudioObjectPropertyListenerBlock = { _, _ in onDeviceLost() }
            var address = Self.aliveAddress
            deviceListener = AudioObjectAddPropertyListenerBlock(device, &address, callbacks, listener) == noErr ? listener : nil
        } else {
            deviceListener = nil
        }
    }

    deinit {
        if let device, let deviceListener {
            var address = Self.aliveAddress
            AudioObjectRemovePropertyListenerBlock(device, &address, callbacks, deviceListener)
        }
        AudioQueueDispose(queue, true)
    }

    func start() throws {
        try Self.check(AudioQueueStart(queue, nil), "start")
    }

    func stop() {
        AudioQueueStop(queue, true)
    }

    private static var aliveAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func use(_ device: AudioDeviceID, on queue: AudioQueueRef) throws {
        guard let uid = InputDevice.uid(of: device) else { throw MicrophoneError(step: "read device", status: kAudioHardwareBadDeviceError) }
        var cfUID = uid as CFString
        try check(AudioQueueSetProperty(queue, kAudioQueueProperty_CurrentDevice, &cfUID, UInt32(MemoryLayout<CFString>.size)), "select device")
    }

    private static func check(_ status: OSStatus, _ step: String) throws {
        guard status == noErr else { throw MicrophoneError(step: step, status: status) }
    }
}
