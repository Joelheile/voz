import CoreGraphics
import Testing
@testable import VozCore

@Suite struct DictationHintTests {
    @Test func tapModifierUsesLowercaseSide() {
        #expect(DictationHint.idle(hotkey: .rightCommand, holdToTalk: false) == "Tap right ⌘ to dictate")
    }

    @Test func holdModifier() {
        let hotkey = Hotkey(keyCode: 61, modifiers: .maskAlternate)
        #expect(DictationHint.idle(hotkey: hotkey, holdToTalk: true) == "Hold right ⌥ to dictate")
    }

    @Test func chordUsesPress() {
        let hotkey = Hotkey(keyCode: 2, modifiers: .maskCommand)
        #expect(DictationHint.idle(hotkey: hotkey, holdToTalk: false) == "Press ⌘D to dictate")
    }

    @Test func fnKeepsName() {
        let hotkey = Hotkey(keyCode: 63, modifiers: [])
        #expect(DictationHint.idle(hotkey: hotkey, holdToTalk: false) == "Tap Fn to dictate")
    }

    @Test func recordingHints() {
        #expect(DictationHint.recording(hotkey: .rightCommand, holdToTalk: true) == "Release right ⌘ to finish")
        #expect(DictationHint.recording(hotkey: .rightCommand, holdToTalk: false) == "Tap right ⌘ again to finish")
    }
}
