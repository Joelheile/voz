import Testing
@testable import VozCore

@Suite struct PackageSourceTests {
    private let base = fileURL("/tmp")

    @Test(arguments: [("voz-jira", "npm:voz-jira"), ("voz-jira@1.2.0", "npm:voz-jira@1.2.0"), ("@me/voz-jira", "npm:@me/voz-jira"), ("npm:voz-jira", "npm:voz-jira")])
    func bareNamesInstallFromNpm(raw: String, expected: String) throws {
        #expect(try PackageSource(parsing: raw, relativeTo: base).description == expected)
    }

    @Test func pathsStayLocal() throws {
        #expect(try PackageSource(parsing: "./voz-jira", relativeTo: base) == .local(fileURL("/tmp/voz-jira")))
    }

    @Test(arguments: ["Voz Jira", "voz-jira@1.0;echo"])
    func invalidNamesFail(raw: String) {
        #expect(throws: PackageSourceError.unrecognized(raw)) { try PackageSource(parsing: raw, relativeTo: base) }
    }
}
