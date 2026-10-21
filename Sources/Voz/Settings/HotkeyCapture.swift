import AppKit
import Combine
import VozCore

@MainActor
final class HotkeyCapture: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var warning: String?
    @Published private(set) var preview: Hotkey?

    private let settings: AppSettings
    private var monitor: Any?
    private var heldKey: UInt16?

    init(settings: AppSettings) {
        self.settings = settings
    }

    func begin() {
        guard !isListening else { return }
        isListening = true
        warning = nil
        settings.isCapturingHotkey = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            MainActor.assumeIsolated { self.handle(event) }
            return nil
        }
    }

    func cancel() {
        guard isListening else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        preview = nil
        heldKey = nil
        isListening = false
        settings.isCapturingHotkey = false
    }

    private func handle(_ event: NSEvent) {
        let flags = event.cgEvent?.flags ?? []
        switch event.type {
        case .keyDown:
            guard !event.isARepeat else { return }
            if event.keyCode == 53, flags.intersection(Hotkey.relevantModifiers).isEmpty {
                cancel()
                return
            }
            heldKey = event.keyCode
            preview = Hotkey(keyCode: event.keyCode, modifiers: flags)
        case .keyUp:
            if event.keyCode == heldKey { heldKey = nil }
            commitIfReleased(flags)
        case .flagsChanged:
            grow(keyCode: event.keyCode, flags: flags)
            commitIfReleased(flags)
        default:
            break
        }
    }

    private func grow(keyCode: UInt16, flags: CGEventFlags) {
        guard heldKey == nil, preview?.isModifierOnly ?? true else { return }
        let candidate = Hotkey(keyCode: keyCode, modifiers: flags)
        guard let ownFlag = candidate.ownModifierFlag, flags.contains(ownFlag) else { return }
        if let preview, !candidate.modifiers.isStrictSuperset(of: preview.modifiers) { return }
        preview = candidate
    }

    private func commitIfReleased(_ flags: CGEventFlags) {
        guard heldKey == nil, flags.intersection(Hotkey.chordModifiers).isEmpty, let preview else { return }
        commit(preview)
    }

    private func commit(_ hotkey: Hotkey) {
        settings.hotkey = hotkey
        warning = SystemShortcuts.warning(for: hotkey)
        cancel()
    }
}
