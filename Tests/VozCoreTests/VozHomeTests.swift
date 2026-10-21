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
        #expect(home.hasEnabledExtensions)
    }

    @Test func pipelineChoicesDefaultRoundTripAndKeepOtherSettings() throws {
        let home = temporaryHome()
        #expect(try home.pipelineChoices() == .standard)
        try home.setPackageSources(["npm:voz-a"])
        let before = try home.extensionSettings()
        let choices = PipelineChoices(speechModel: "whisper/base", cleanupModel: "llm/fast", cleanupSteps: ["llm/jira", "model"])
        try home.setPipelineChoices(choices)
        #expect(try home.pipelineChoices() == choices)
        #expect(try home.packageSources() == ["npm:voz-a"])
        #expect(try home.extensionSettings() == before)
    }

    @Test func malformedPipelineFailsLoudlyAndStaysUntouched() throws {
        let home = temporaryHome()
        let settings = #"{"cleanupSteps":"model"}"#
        try writeFile(settings, named: "settings.json", in: home.root)
        #expect(throws: VozHomeError.self) { try home.pipelineChoices() }
        #expect(throws: VozHomeError.self) { try home.setPipelineChoices(.standard) }
        #expect(fileContents(home.settings) == settings)
    }

    @Test func installedExtensionsAreLooseFilesAndPackagesByTheirOwnName() throws {
        let home = temporaryHome()
        #expect(!home.hasEnabledExtensions)
        try writeFile("export default () => {}", named: "notes.ts", in: home.extensions)
        try writeFile("export default () => {}", named: "index.ts", in: home.extensions.appendingPathComponent("folder"))
        try writeFile("", named: "README.md", in: home.extensions)
        let pack = home.root.appendingPathComponent("pack-src")
        try writeFile(#"{"name":"voz-pack"}"#, named: "package.json", in: pack)
        try home.setPackageSources([pack.path])
        #expect(try home.installedExtensions().map(\.name) == ["folder", "notes", "voz-pack"])
        #expect(try home.installedExtensions().last?.source?.directory(in: home).standardizedFileURL.path == pack.standardizedFileURL.path)
        for name in ["folder", "notes"] { try home.setExtension(name, enabled: false) }
        #expect(home.hasEnabledExtensions)
        try home.setExtension("voz-pack", enabled: false)
        #expect(!home.hasEnabledExtensions)
    }

    @Test func turningExtensionsOffAndOnKeepsOtherSettings() throws {
        let home = temporaryHome()
        try home.setPackageSources(["npm:voz-a"])
        try home.setExtension("voz-a", enabled: false)
        try home.setExtension("notes", enabled: false)
        try home.setExtension("voz-a", enabled: true)
        #expect(try home.disabledExtensions() == ["notes"])
        #expect(try home.packageSources() == ["npm:voz-a"])
    }

    @Test func configRoundTripsTypedValuesAndKeepsOtherSettings() throws {
        let home = temporaryHome()
        try writeFile(#"{"packages":["npm:voz-jira"],"config":{"jira":{"project":"VOZ","nested":{"a":1}},"other":{"x":1}}}"#, named: "settings.json", in: home.root)
        try home.setConfig(.number(3), key: "count", for: "jira")
        try home.setConfig(.boolean(false), key: "on", for: "jira")
        try home.setConfig(.string("WEB"), key: "project", for: "jira")
        #expect(try home.config(for: "jira") == ["project": .string("WEB"), "count": .number(3), "on": .boolean(false)])
        #expect(try home.config(for: "other") == ["x": .number(1)])
        #expect(try home.config(for: "missing") == [:])
        #expect(try home.packageSources() == ["npm:voz-jira"])
    }

    @Test func malformedConfigFailsLoudly() throws {
        let home = temporaryHome()
        try writeFile(#"{"config":{"jira":"VOZ"}}"#, named: "settings.json", in: home.root)
        #expect(throws: VozHomeError.self) { try home.config(for: "jira") }
        #expect(throws: VozHomeError.self) { try home.setConfig(.string("x"), key: "project", for: "jira") }
    }
}
