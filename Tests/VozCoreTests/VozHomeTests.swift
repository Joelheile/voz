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

    @Test func authoringFilesGiveEditorsTypesAndAgentsAGuide() throws {
        let resources = hostScript.deletingLastPathComponent()
        try home.writeAuthoringFiles(from: resources)
        try home.writeAuthoringFiles(from: resources)
        #expect(fileContents(home.root.appendingPathComponent("node_modules/voz/index.d.ts"))?.contains("defineExtension") == true)
        #expect(fileContents(home.root.appendingPathComponent("AGENTS.md"))?.contains("beforeCleanup") == true)
        #expect(!home.hasExtensions)
    }

    @Test func typesGoIntoAnyFolderVozDevLoads() throws {
        let folder = temporaryHome().root
        try VozHome.writeTypes(into: folder, from: hostScript.deletingLastPathComponent())
        #expect(fileContents(folder.appendingPathComponent("node_modules/voz/index.d.ts"))?.contains("defineExtension") == true)
    }

    @Test func looseExtensionFileCounts() throws {
        try writeFile("export default () => {}", named: "hello.ts", in: home.extensions)
        #expect(home.hasExtensions)
    }
}
