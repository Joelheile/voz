import Testing
@testable import VozCore

struct SettingFieldTests {
    private func field(_ json: String) throws -> SettingField {
        try decodeJSON(SettingField.self, json)
    }

    @Test func usesTheStoredValueOnlyWhenItFits() throws {
        let mode = try field(#"{"key":"mode","type":"string","title":"Mode","default":"quiet","options":["quiet","casual"]}"#)
        #expect(mode.value(in: ["mode": .string("casual")]) == .string("casual"))
        #expect(mode.value(in: ["mode": .string("loud")]) == .string("quiet"))
        #expect(mode.value(in: ["mode": .number(1)]) == .string("quiet"))
        #expect(mode.value(in: [:]) == .string("quiet"))
    }

    @Test func decodesBooleansNumbersAndStringsApart() throws {
        #expect(try field(#"{"key":"a","type":"boolean","title":"A","default":true}"#).default == .boolean(true))
        #expect(try field(#"{"key":"a","type":"number","title":"A","default":1}"#).default == .number(1))
        #expect(try field(#"{"key":"a","type":"string","title":"A","default":"1"}"#).default == .string("1"))
    }

    @Test func requiredSettingsNeedAValueUntilSet() throws {
        let token = try field(#"{"key":"token","type":"string","title":"Token","default":"","required":true}"#)
        #expect(token.needsValue(in: [:]))
        #expect(!token.needsValue(in: ["token": .string("abc")]))
        #expect(!(try field(#"{"key":"token","type":"string","title":"Token","default":""}"#)).needsValue(in: [:]))
    }

    @Test func showsWholeNumbersWithoutDecimals() {
        #expect(SettingValue.number(3).text == "3")
        #expect(SettingValue.number(2.5).text == "2.5")
    }
}
