import Testing
@testable import VozCore

@Suite struct TextSpliceTests {
    @Test func replacesRangesAndKeepsPunctuation() {
        let text = "Open Vos, then close Vos."
        let edits = [
            TextEdit(utf8Range: 5..<8, replacement: "Voz"),
            TextEdit(utf8Range: 21..<24, replacement: "Voz"),
        ]
        #expect(TextSplice.apply(edits, to: text) == "Open Voz, then close Voz.")
    }

    @Test func handlesMultibyteText() {
        let text = "Grüße Vos"
        #expect(TextSplice.apply([TextEdit(utf8Range: 8..<11, replacement: "Voz")], to: text) == "Grüße Voz")
    }

    @Test func skipsOverlappingAndOutOfRangeEdits() {
        let text = "abcdef"
        let edits = [
            TextEdit(utf8Range: 1..<4, replacement: "X"),
            TextEdit(utf8Range: 3..<5, replacement: "Y"),
            TextEdit(utf8Range: 5..<99, replacement: "Z"),
        ]
        #expect(TextSplice.apply(edits, to: text) == "abcYf")
    }
}
