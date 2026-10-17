import CoreAudio
import Foundation

@MainActor
final class OutputMuter {
    private static let mutedByVozKey = "mutedByVoz"

    private let defaults = UserDefaults.standard

    func restoreLeftoverMute() {
        guard defaults.bool(forKey: Self.mutedByVozKey) else { return }
        Log.app.notice("Found mute left by a previous run, unmuting")
        guard let device = defaultOutputDevice() else { return }
        if setMuted(false, on: device) {
            defaults.removeObject(forKey: Self.mutedByVozKey)
        }
    }

    func mute() {
        guard let device = defaultOutputDevice() else { return }
        guard let wasMuted = isMuted(device) else {
            Log.app.warning("Default output device has no mute control, skipping mute")
            return
        }
        guard !wasMuted else { return }
        defaults.set(true, forKey: Self.mutedByVozKey)
        if !setMuted(true, on: device) {
            defaults.removeObject(forKey: Self.mutedByVozKey)
        }
    }

    func unmuteIfMutedByVoz() {
        guard defaults.bool(forKey: Self.mutedByVozKey) else { return }
        guard let device = defaultOutputDevice() else { return }
        if setMuted(false, on: device) {
            defaults.removeObject(forKey: Self.mutedByVozKey)
        } else {
            Log.app.error("Unmute did not read back, keeping mutedByVoz flag")
        }
    }

    private func defaultOutputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        guard status == noErr, device != kAudioObjectUnknown else {
            Log.app.error("Default output device lookup failed: \(status)")
            return nil
        }
        return device
    }

    private var muteAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func isMuted(_ device: AudioDeviceID) -> Bool? {
        var address = muteAddress
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        guard status == noErr else {
            Log.app.error("Mute read failed: \(status)")
            return nil
        }
        return value != 0
    }

    private func setMuted(_ muted: Bool, on device: AudioDeviceID) -> Bool {
        var address = muteAddress
        var value: UInt32 = muted ? 1 : 0
        let status = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        guard status == noErr else {
            Log.app.error("Mute write failed: \(status)")
            return false
        }
        let readBack = isMuted(device)
        guard readBack == muted else {
            Log.app.error("Mute read back \(String(describing: readBack)), expected \(muted)")
            return false
        }
        return true
    }
}
