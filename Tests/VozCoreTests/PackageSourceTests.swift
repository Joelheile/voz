import Testing
@testable import VozCore

struct PackageSourceTests {
    private let base = fileURL("/Users/me/work")
    private let home = VozHome(root: fileURL("/Users/me/.voz"))

    @Test func parsesScopedNpmPackageWithVersion() throws {
        let source = try PackageSource(parsing: "npm:@acme/voz-slack@1.2.0", relativeTo: base)
        #expect(source == .npm(name: "@acme/voz-slack", spec: "@acme/voz-slack@1.2.0"))
        #expect(source.description == "npm:@acme/voz-slack@1.2.0")
        #expect(source.directory(in: home).path == "/Users/me/.voz/packages/node_modules/@acme/voz-slack")
    }

    @Test func parsesUnscopedNpmPackage() throws {
        #expect(try PackageSource(parsing: "npm:voz-jira", relativeTo: base) == .npm(name: "voz-jira", spec: "voz-jira"))
        #expect(try PackageSource(parsing: "npm:voz-jira@2", relativeTo: base) == .npm(name: "voz-jira", spec: "voz-jira@2"))
    }

    @Test func parsesGitSourceWithRef() throws {
        let source = try PackageSource(parsing: "git:github.com/acme/voz-jira@v1.0.0", relativeTo: base)
        #expect(source == .git(host: "github.com", path: "acme/voz-jira", ref: "v1.0.0"))
        #expect(source.description == "git:github.com/acme/voz-jira@v1.0.0")
        #expect(source.directory(in: home).path == "/Users/me/.voz/packages/git/github.com/acme/voz-jira")
        #expect(source.cloneURL == "https://github.com/acme/voz-jira")
    }

    @Test func parsesHttpsURLAsGit() throws {
        let source = try PackageSource(parsing: "https://github.com/acme/voz-jira.git", relativeTo: base)
        #expect(source == .git(host: "github.com", path: "acme/voz-jira", ref: nil))
    }

    @Test func resolvesLocalPathsAgainstBase() throws {
        let source = try PackageSource(parsing: "./my-pack", relativeTo: base)
        #expect(source == .local(fileURL("/Users/me/work/my-pack")))
        #expect(source.description == "/Users/me/work/my-pack")
        #expect(try PackageSource(parsing: "/opt/pack", relativeTo: base).directory(in: home).path == "/opt/pack")
    }

    @Test func rejectsUnknownSources() {
        #expect(throws: PackageSourceError.unrecognized("voz-jira")) { try PackageSource(parsing: "voz-jira", relativeTo: base) }
        #expect(throws: PackageSourceError.unrecognized("git:github.com")) { try PackageSource(parsing: "git:github.com", relativeTo: base) }
        #expect(throws: PackageSourceError.unrecognized("npm:")) { try PackageSource(parsing: "npm:", relativeTo: base) }
    }

    @Test func namesMatchTheLastPathComponentOrPackageName() throws {
        #expect(try PackageSource(parsing: "git:github.com/acme/voz-jira@v1", relativeTo: base).name == "voz-jira")
        #expect(try PackageSource(parsing: "npm:@acme/voz-slack@1", relativeTo: base).name == "@acme/voz-slack")
        #expect(try PackageSource(parsing: "/opt/my-pack", relativeTo: base).name == "my-pack")
    }
}
