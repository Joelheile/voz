import CoreGraphics
import Testing
@testable import VozCore

@Suite struct HotkeyTests {
    @Test func roundTripsThroughJSON() throws {
        let hotkey = Hotkey(keyCode: 49, modifiers: [.maskControl, .maskAlternate])
        #expect(try roundTripThroughJSON(hotkey) == hotkey)
    }

    @Test func modifiersOutsideTheRelevantSetAreDropped() {
        let hotkey = Hotkey(keyCode: 63, modifiers: .maskSecondaryFn)
        #expect(hotkey.modifiers.isEmpty)
        #expect(hotkey.isModifierOnly)
    }

    @Test func displayNames() {
        #expect(Hotkey.rightCommand.displayName == "Right ⌘")
        #expect(Hotkey(keyCode: 49, modifiers: [.maskControl, .maskAlternate]).displayName == "⌃⌥Space")
        #expect(Hotkey(keyCode: 96, modifiers: []).displayName == "F5")
    }

    @Test func warnsForSystemShortcuts() {
        #expect(SystemShortcuts.warning(for: Hotkey(keyCode: 49, modifiers: .maskCommand)) != nil)
        #expect(SystemShortcuts.warning(for: Hotkey(keyCode: 49, modifiers: .maskControl)) != nil)
        #expect(SystemShortcuts.warning(for: Hotkey(keyCode: 9, modifiers: .maskCommand)) != nil)
        #expect(SystemShortcuts.warning(for: .rightCommand) == nil)
        #expect(SystemShortcuts.warning(for: Hotkey(keyCode: 49, modifiers: [.maskControl, .maskAlternate])) == nil)
    }
}
