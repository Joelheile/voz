import CoreAudio
import Foundation

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
