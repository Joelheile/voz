import CoreAudio

/// Bluetooth headphones drop to call quality while their own mic records. When they connect and macOS hands them the mic, this hands it back.
/// A mic you pick yourself later stays picked: only a takeover within moments of connecting counts.
struct HeadphoneTakeover {
    static let connectWindow: Duration = .seconds(5)

    private var inputs: Set<String>
    private var connectedAt: [String: ContinuousClock.Instant] = [:]
    private var current: String?

    init(inputs: Set<String>, current: String?) {
        self.inputs = inputs
        self.current = current
    }

    mutating func inputsChanged(to latest: Set<String>, at now: ContinuousClock.Instant) {
        for uid in latest.subtracting(inputs) { connectedAt[uid] = now }
        inputs = latest
    }

    /// The mic to switch back to, or nil to accept the new default
    mutating func defaultChanged(to uid: String, isBluetooth: Bool, at now: ContinuousClock.Instant) -> String? {
        let justConnected = !inputs.contains(uid) || connectedAt[uid].map { now - $0 < Self.connectWindow } ?? false
        if isBluetooth, justConnected, let previous = current, previous != uid, inputs.contains(previous) {
            return previous
        }
        current = uid
        return nil
    }
}

@MainActor
final class HeadphoneQuality {
    private var takeover: HeadphoneTakeover?
    private var listener: AudioObjectPropertyListenerBlock?

    var isOn: Bool = false {
        didSet {
            guard isOn != oldValue else { return }
            isOn ? start() : stop()
        }
    }

    private func start() {
        takeover = HeadphoneTakeover(inputs: InputDevice.inputUIDs(), current: InputDevice.defaultInput().flatMap(InputDevice.uid))
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.audioDevicesChanged() }
        }
        for var address in Self.addresses {
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        }
        self.listener = listener
    }

    private func stop() {
        guard let listener else { return }
        for var address in Self.addresses {
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        }
        self.listener = nil
        takeover = nil
    }

    private func audioDevicesChanged() {
        let now = ContinuousClock.now
        takeover?.inputsChanged(to: InputDevice.inputUIDs(), at: now)
        guard let device = InputDevice.defaultInput(), let uid = InputDevice.uid(of: device),
              let previous = takeover?.defaultChanged(to: uid, isBluetooth: InputDevice.isBluetooth(device), at: now),
              let restored = InputDevice.connected(uid: previous)
        else { return }
        if InputDevice.setDefaultInput(restored) {
            Log.app.notice("Kept the mic when Bluetooth headphones connected")
        } else {
            Log.app.error("Could not keep the mic when Bluetooth headphones connected")
        }
    }

    private static let addresses = [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice].map {
        AudioObjectPropertyAddress(mSelector: $0, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }
}
