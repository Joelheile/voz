import Testing
import VozCore

@Suite struct VozHomeTests {
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

    @Test func configRoundTripsTypedValuesAndKeepsOtherSettings() throws {
        let home = temporaryHome()
        try writeFile(#"{"packages":["npm:voz-jira"],"config":{"jira":{"project":"VOZ","nested":{"a":1}},"other":{"x":1}}}"#, named: "settings.json", in: home.root)
        try home.setConfig(.number(3), key: "count", for: "jira")
        try home.setConfig(.boolean(false), key: "on", for: "jira")
        try home.setConfig(.string("WEB"), key: "project", for: "jira")
        #expect(posixPermissions(home.root) == 0o700)
        #expect(posixPermissions(home.settings) == 0o600)
        #expect(try home.config(for: "jira") == ["project": .string("WEB"), "count": .number(3), "on": .boolean(false)])
        #expect(try home.config(for: "other") == ["x": .number(1)])
        #expect(try home.config(for: "missing") == [:])
        #expect(try home.packageSources() == ["npm:voz-jira"])
    }
}
