import Testing
@testable import VozCore

@Suite struct PackageListingTests {
    @Test func readsTheLatestVersionFromTheRegistry() throws {
        let json = #"{"name":"voz-jira","description":"Jira keys","dist-tags":{"latest":"1.2.0"},"versions":{"1.1.0":{"_npmUser":{"name":"old"}},"1.2.0":{"_npmUser":{"name":"mara"}}},"time":{"1.2.0":"2026-10-20T10:00:00.000Z"}}"#
        let listing = try PackageListing.decodePackument(jsonData(json))
        #expect(listing.name == "voz-jira")
        #expect(listing.version == "1.2.0")
        #expect(listing.publisher == "mara")
        #expect(listing.published != nil)
        #expect(listing.page?.absoluteString == "https://www.npmjs.com/package/voz-jira")
    }

    @Test func packagesWithoutAReleaseFail() {
        let json = #"{"name":"voz-jira","dist-tags":{},"versions":{},"time":{}}"#
        #expect(throws: DecodingError.self) { try PackageListing.decodePackument(jsonData(json)) }
    }

    @Test(arguments: [
        ("voz://extensions/voz-jira", "voz-jira"),
        ("voz://extensions/@me/voz-jira", "@me/voz-jira"),
        ("voz://extensions/%40me%2Fvoz-jira", "@me/voz-jira"),
    ])
    func linksNameNpmPackages(link: String, name: String) {
        #expect(webURL(link).flatMap(ExtensionLink.packageName(in:)) == name)
    }

    @Test(arguments: ["voz://extensions/Voz Jira", "voz://extensions/voz-jira@1.0.0", "voz://extensions/", "voz://settings/voz-jira", "https://extensions/voz-jira"])
    func rejectsOtherLinks(link: String) {
        #expect(webURL(link).flatMap(ExtensionLink.packageName(in:)) == nil)
    }
}
