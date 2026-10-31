import AppKit
import CoreAudio

struct Microphone: Hashable, Sendable {
    let uid: String
    let name: String
    let kind: String
}

enum InputDevice {
    static func microphones() -> [Microphone] {
        allDevices().filter(hasInputStreams).compactMap { device in
            guard let uid = string(kAudioDevicePropertyDeviceUID, of: device), let name = name(of: device) else { return nil }
            return Microphone(uid: uid, name: name, kind: kind(of: device))
        }
    }

    static func defaultName() -> String? {
        defaultInput().flatMap(name)
    }

    private static func name(of device: AudioDeviceID) -> String? {
        string(kAudioObjectPropertyName, of: device)
    }

    static func connected(uid: String) -> AudioDeviceID? {
        guard !uid.isEmpty else { return nil }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfUID = uid as CFString
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafeMutablePointer(to: &cfUID) { pointer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address,
                UInt32(MemoryLayout<CFString>.size), pointer, &size, &device
            )
        }
        guard status == noErr, device != kAudioObjectUnknown, hasInputStreams(device) else { return nil }
        return device
    }

    static func builtInIfDefaultIsBluetooth() -> AudioDeviceID? {
        guard let defaultDevice = defaultInput(), isBluetooth(defaultDevice) else { return nil }
        return allDevices().first { transportType($0) == kAudioDeviceTransportTypeBuiltIn && hasInputStreams($0) }
    }

    static func isRunningSomewhere() -> Bool {
        guard let device = defaultInput() else { return false }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr && running != 0
    }

    static func defaultInput() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    private static func allDevices() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices) == noErr else { return [] }
        return devices
    }

    private static func transportType(_ device: AudioDeviceID) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func kind(of device: AudioDeviceID) -> String {
        switch transportType(device) {
        case kAudioDeviceTransportTypeBuiltIn: "Built in"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: "Bluetooth"
        case kAudioDeviceTransportTypeUSB: "USB"
        case kAudioDeviceTransportTypeContinuityCaptureWired, kAudioDeviceTransportTypeContinuityCaptureWireless: "iPhone"
        case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate: "Virtual"
        default: "External"
        }
    }

    private static func string(_ selector: AudioObjectPropertySelector, of device: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private static func isBluetooth(_ device: AudioDeviceID) -> Bool {
        let transport = transportType(device)
        return transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    private static func hasInputStreams(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
    }
}

final class OutputMuter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.joelheile.voz.mute")
    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var ioProc: AudioDeviceIOProcID?

    func mute() {
        queue.async { self.startMuting() }
    }

    func unmute() {
        queue.async { self.stopMuting() }
    }

    private func startMuting() {
        guard tap == kAudioObjectUnknown else { return }
        let started = ContinuousClock.now
        do {
            try startMutingTap()
            Log.app.notice("Muted other apps in \((ContinuousClock.now - started).wholeMilliseconds) ms")
        } catch {
            Log.app.error("Mute failed: \(error.localizedDescription, privacy: .public)")
            Analytics.report(.muteFailed)
            stopMuting()
        }
    }

    private func stopMuting() {
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

    private func startMutingTap() throws {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: Self.ownProcessObject.map { [$0] } ?? [])
        description.muteBehavior = .muted
        description.isPrivate = true
        try check(AudioHardwareCreateProcessTap(description, &tap), "create tap")
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Voz mute",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString]],
        ]
        try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &device), "create aggregate device")
        try check(AudioDeviceCreateIOProcIDWithBlock(&ioProc, device, nil) { _, _, _, _, _ in }, "create IO proc")
        try check(AudioDeviceStart(device, ioProc), "start IO")
    }

    private func check(_ status: OSStatus, _ step: String) throws {
        guard status == noErr else { throw MuteError(step: step, status: status) }
    }

    private static var ownProcessObject: AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var pid = getpid()
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object)
        guard status == noErr, object != kAudioObjectUnknown else { return nil }
        return object
    }
}

private struct MuteError: LocalizedError {
    let step: String
    let status: OSStatus

    var errorDescription: String? { "\(step) returned \(status)" }
}

enum SoundCue: String {
    case start
    case stop
}

@MainActor
enum SoundCues {
    private static var current: NSSound?

    @discardableResult
    static func play(_ cue: SoundCue) -> Bool {
        guard
            let url = Bundle.main.url(forResource: cue.rawValue, withExtension: "wav", subdirectory: "Sounds"),
            let sound = NSSound(contentsOf: url, byReference: true)
        else {
            Log.app.error("Sound cue missing: \(cue.rawValue)")
            return false
        }
        current = sound
        return sound.play()
    }
}
