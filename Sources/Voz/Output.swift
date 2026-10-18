import AppKit
import VozCore

@MainActor
final class TextOutput {
    private static let pasteDelay: TimeInterval = 0.05

    private let settings: AppSettings
    private var pendingRestore: (snapshot: [[NSPasteboard.PasteboardType: Data]], task: Task<Void, Never>)?

    init(settings: AppSettings) {
        self.settings = settings
    }

    func deliver(_ text: String) async {
        let output = settings.output
        guard output.copyToClipboard || output.pasteIntoActiveApp else { return }
        let pasteboard = NSPasteboard.general
        pendingRestore?.task.cancel()
        let snapshot = output.needsClipboardRestore ? pendingRestore?.snapshot ?? Self.snapshot(of: pasteboard) : nil
        pendingRestore = nil
        let changeCountAtWrite = write(text, to: pasteboard, markers: PasteboardMarkers.types(copyToClipboard: output.copyToClipboard))
        guard output.pasteIntoActiveApp else { return }
        guard AXIsProcessTrusted() else {
            Log.app.error("Accessibility not granted, text copied but not pasted")
            return
        }
        try? await Task.sleep(for: .seconds(Self.pasteDelay))
        guard let keyCode = KeyboardLayout.keyCode(producing: "v") else {
            Log.app.error("No key produces v on the current keyboard layout, text copied but not pasted")
            return
        }
        Self.post(keyCode: CGKeyCode(keyCode), flags: .maskCommand)
        guard let snapshot else { return }
        let task = Task { [weak self] in
            guard (try? await Task.sleep(for: .seconds(ClipboardRestoreGuard.delay))) != nil else { return }
            self?.pendingRestore = nil
            if ClipboardRestoreGuard.shouldRestore(changeCountAtWrite: changeCountAtWrite, currentChangeCount: pasteboard.changeCount) {
                Self.restore(snapshot, to: pasteboard)
            }
        }
        pendingRestore = (snapshot, task)
    }

    func press(_ chord: KeyChord) {
        guard AXIsProcessTrusted() else {
            Log.app.error("Accessibility not granted, key press skipped")
            return
        }
        switch chord.key {
        case .code(let code):
            Self.post(keyCode: CGKeyCode(code), flags: chord.modifiers.eventFlags)
        case .character(let character):
            guard let code = KeyboardLayout.keyCode(producing: character) else {
                Log.app.error("No key produces \(character, privacy: .public) on the current keyboard layout")
                return
            }
            Self.post(keyCode: CGKeyCode(code), flags: chord.modifiers.eventFlags)
        }
    }

    func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func write(_ text: String, to pasteboard: NSPasteboard, markers: [String]) -> Int {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        for marker in markers { item.setData(Data(), forType: NSPasteboard.PasteboardType(marker)) }
        pasteboard.writeObjects([item])
        return pasteboard.changeCount
    }

    private static func snapshot(of pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            var stored: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { stored[type] = data }
            }
            return stored
        }
    }

    private static func restore(_ snapshot: [[NSPasteboard.PasteboardType: Data]], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let items = snapshot.map { stored -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in stored { item.setData(data, forType: type) }
            return item
        }
        pasteboard.writeObjects(items)
    }

    private static func post(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }
}
