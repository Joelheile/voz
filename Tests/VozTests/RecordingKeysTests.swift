import CoreGraphics
import Testing
@testable import Voz

@Suite struct RecordingKeysTests {
    private let returnKey = RecordingKeyFilter.returnKey
    private let escape = RecordingKeyFilter.escape

    @Test func escCancelsAndReturnSendsOnlyWithQuickSend() {
        let on = RecordingKeyFilter(hotkey: .rightCommand, quickSend: true)
        let off = RecordingKeyFilter(hotkey: .rightCommand, quickSend: false)
        #expect(on.key(for: escape, flags: []) == .cancel)
        #expect(off.key(for: escape, flags: []) == .cancel)
        #expect(on.key(for: returnKey, flags: []) == .send)
        #expect(on.key(for: RecordingKeyFilter.keypadEnter, flags: []) == .send)
        #expect(off.key(for: returnKey, flags: []) == nil)
        #expect(on.key(for: 0, flags: []) == nil)
    }

    @Test func returnStillSendsWhileYouHoldTheHotkeyButShortcutsPassThrough() {
        let filter = RecordingKeyFilter(hotkey: .rightCommand, quickSend: true)
        #expect(filter.key(for: returnKey, flags: .maskCommand) == .send)
        #expect(filter.key(for: returnKey, flags: [.maskCommand, .maskShift]) == nil)
        #expect(filter.key(for: returnKey, flags: .maskShift) == nil)
        #expect(filter.key(for: escape, flags: .maskAlternate) == nil)
        #expect(filter.key(for: returnKey, flags: .maskAlphaShift) == .send)
    }

    @Test func aHotkeyOnReturnOrEscKeepsWorking() {
        let onReturn = RecordingKeyFilter(hotkey: Hotkey(keyCode: 36, modifiers: []), quickSend: true)
        #expect(onReturn.key(for: returnKey, flags: []) == nil)
        #expect(onReturn.key(for: escape, flags: []) == .cancel)
        let onEscape = RecordingKeyFilter(hotkey: Hotkey(keyCode: 53, modifiers: []), quickSend: true)
        #expect(onEscape.key(for: escape, flags: []) == nil)
        let onOptionReturn = RecordingKeyFilter(hotkey: Hotkey(keyCode: 36, modifiers: .maskAlternate), quickSend: true)
        #expect(onOptionReturn.key(for: returnKey, flags: []) == nil)
    }
}
