import Testing
@testable import VozCore

struct KeyCodeSearchTests {
    @Test func findsQwertyV() {
        let qwerty: [UInt16: String] = [9: "v", 11: "b"]
        #expect(KeyCodeSearch.keyCode(producing: "v") { qwerty[$0] } == 9)
    }

    @Test func findsRelocatedKeyOnDvorak() {
        let dvorak: [UInt16: String] = [9: ".", 47: "v"]
        #expect(KeyCodeSearch.keyCode(producing: "v") { dvorak[$0] } == 47)
    }

    @Test func returnsNilWhenLayoutLacksTheCharacter() {
        #expect(KeyCodeSearch.keyCode(producing: "v") { _ in "x" } == nil)
    }

    @Test func currentLayoutResolvesToAKeyThatTypesV() {
        let code = KeyboardLayout.keyCode(producing: "v")
        #expect(code != nil)
        #expect((code ?? .max) < KeyCodeSearch.keyCount)
    }
}
