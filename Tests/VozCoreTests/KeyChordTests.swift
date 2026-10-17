import Testing
@testable import VozCore

struct KeyChordTests {
    @Test func namedKeyWithoutModifiers() throws {
        #expect(try KeyChord(parsing: "return") == KeyChord(key: .code(36), modifiers: []))
    }

    @Test func modifiersAndCharacter() throws {
        let chord = try KeyChord(parsing: "Cmd+Shift+k")
        #expect(chord == KeyChord(key: .character("k"), modifiers: [.command, .shift]))
    }

    @Test func modifierAliases() throws {
        #expect(try KeyChord(parsing: "ctrl+opt+tab").modifiers == [.control, .option])
        #expect(try KeyChord(parsing: "command+alt+control+space").modifiers == [.command, .option, .control])
    }

    @Test func rejectsUnknownKeysAndModifiers() {
        #expect(throws: KeyChordError.unknownKey("enterr")) { try KeyChord(parsing: "enterr") }
        #expect(throws: KeyChordError.unknownModifier("hyper")) { try KeyChord(parsing: "hyper+a") }
        #expect(throws: KeyChordError.unknownKey("")) { try KeyChord(parsing: "cmd+") }
    }
}
