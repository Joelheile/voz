import Testing
@testable import VozCore

@Suite struct ExtensionTemplateTests {
    private let parent = temporaryHome().root

    @Test func createsANamedProjectWithTypes() throws {
        let folder = try ExtensionTemplate.create(named: "@me/voz-jira", in: parent, from: extensionResources)
        #expect(folder.lastPathComponent == "voz-jira")
        #expect(fileContents(folder.appendingPathComponent("package.json"))?.contains(#""name": "@me/voz-jira""#) == true)
        #expect(fileContents(folder.appendingPathComponent("index.ts"))?.contains("{{name}}") == false)
        #expect(fileContents(folder.appendingPathComponent("voz.d.ts")) == fileContents(extensionResources.appendingPathComponent("voz.d.ts")))
        #expect(ExtensionTemplate.mapsTypes(in: folder))
        #expect(!ExtensionTemplate.mapsTypes(in: parent))
    }

    @Test(arguments: ["Voz-Jira", "voz jira", "", "../voz", "-voz"])
    func rejectsInvalidNames(name: String) {
        #expect(throws: ExtensionTemplateError.invalidName(name)) {
            try ExtensionTemplate.create(named: name, in: parent, from: extensionResources)
        }
    }

    @Test func refusesAnExistingFolder() throws {
        try writeFile("keep", named: "index.ts", in: parent.appendingPathComponent("voz-jira"))
        #expect(throws: ExtensionTemplateError.self) {
            try ExtensionTemplate.create(named: "voz-jira", in: parent, from: extensionResources)
        }
        #expect(fileContents(parent.appendingPathComponent("voz-jira/index.ts")) == "keep")
    }
}
