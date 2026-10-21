import Testing
@testable import VozCore

struct KeyChordTests {
    @Test func parsesNamedKeysCharactersAndModifiers() throws {
        let chord = try KeyChord(parsing: "Cmd+Shift+Return")
        #expect(chord.key == .code(36))
        #expect(chord.modifiers == [.command, .shift])
        #expect(try KeyChord(parsing: "ctrl+opt+j").key == .character("j"))
    }

    @Test func labelsModifiersInMacOrder() throws {
        #expect(try KeyChord(parsing: "cmd+ctrl+opt+shift+j").label == "⌃⌥⇧⌘J")
        #expect(try KeyChord(parsing: "cmd+return").label == "⌘↩")
        #expect(try KeyChord(parsing: "space").label == "Space")
    }

    @Test func rejectsUnknownKeysAndModifiers() {
        #expect(throws: KeyChordError.unknownModifier("hyper")) { try KeyChord(parsing: "hyper+j") }
        #expect(throws: KeyChordError.unknownKey("jj")) { try KeyChord(parsing: "cmd+jj") }
        #expect(throws: KeyChordError.unknownKey("")) { try KeyChord(parsing: "cmd+") }
    }
}
