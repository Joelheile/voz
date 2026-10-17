import AppKit
import Combine
import VozCore

@MainActor
final class HotkeyCapture: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var warning: String?

    private let settings: AppSettings
    private var monitor: Any?
    private var pendingModifier: Hotkey?

    init(settings: AppSettings) {
        self.settings = settings
    }

    func begin() {
        guard !isListening else { return }
        isListening = true
        warning = nil
        settings.isCapturingHotkey = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            MainActor.assumeIsolated { self.handle(event) }
            return nil
        }
    }

    func cancel() {
        guard isListening else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        pendingModifier = nil
        isListening = false
        settings.isCapturingHotkey = false
    }

    private func handle(_ event: NSEvent) {
        let flags = event.cgEvent?.flags ?? []
        switch event.type {
        case .keyDown:
            pendingModifier = nil
            if event.keyCode == 53, flags.intersection(Hotkey.relevantModifiers).isEmpty {
                cancel()
                return
            }
            commit(Hotkey(keyCode: event.keyCode, modifiers: flags))
        case .flagsChanged:
            handleModifier(keyCode: event.keyCode, flags: flags)
        default:
            break
        }
    }

    private func handleModifier(keyCode: UInt16, flags: CGEventFlags) {
        let candidate = Hotkey(keyCode: keyCode, modifiers: flags)
        guard let ownFlag = candidate.ownModifierFlag else { return }
        if flags.contains(ownFlag) {
            let others = flags.intersection(Hotkey.relevantModifiers).subtracting(ownFlag)
            pendingModifier = others.isEmpty ? candidate : nil
        } else if let pending = pendingModifier, pending.keyCode == keyCode {
            commit(pending)
        } else {
            pendingModifier = nil
        }
    }

    private func commit(_ hotkey: Hotkey) {
        settings.hotkey = hotkey
        warning = SystemShortcuts.warning(for: hotkey)
        cancel()
    }
}
