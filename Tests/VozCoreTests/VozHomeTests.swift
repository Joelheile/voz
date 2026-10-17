import Testing
@testable import VozCore

struct VozHomeTests {
    private let home = temporaryHome()

    @Test func emptyHomeHasNoPackagesOrExtensions() throws {
        #expect(try home.packageSources() == [])
        #expect(!home.hasExtensions)
    }

    @Test func savingPackagesKeepsOtherSettings() throws {
        try writeFile(#"{"config":{"jira":{"project":"VOZ"}}}"#, named: "settings.json", in: home.root)
        try home.setPackageSources(["npm:voz-jira", "git:github.com/acme/voz-slack"])

        #expect(try home.packageSources() == ["npm:voz-jira", "git:github.com/acme/voz-slack"])
        #expect(try storedConfig(in: home)?["jira"]?["project"] == "VOZ")
        #expect(home.hasExtensions)
    }

    @Test func looseExtensionFileCounts() throws {
        try writeFile("export default () => {}", named: "hello.ts", in: home.extensions)
        #expect(home.hasExtensions)
    }
}
