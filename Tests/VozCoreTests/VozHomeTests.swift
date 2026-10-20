import Testing
@testable import VozCore

@Suite struct VozHomeTests {
    @Test(arguments: [#"["npm:voz-a"]"#, #"{"packages":"npm:voz-a"}"#])
    func malformedSettingsFailLoudlyAndStayUntouched(settings: String) throws {
        let home = temporaryHome()
        try writeFile(settings, named: "settings.json", in: home.root)
        #expect(throws: VozHomeError.self) { try home.packageSources() }
        #expect(throws: VozHomeError.self) { try home.setPackageSources(["npm:voz-b"]) }
        #expect(fileContents(home.settings) == settings)
        #expect(home.hasExtensions)
    }
}
