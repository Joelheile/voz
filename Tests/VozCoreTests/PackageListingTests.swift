import Testing
@testable import VozCore

struct PackageListingTests {
    private let search = utf8Data("""
    {"objects": [
      {"package": {"name": "voz-quiet", "version": "1.0.0", "publisher": {"username": "ann"}, "links": {"npm": "http://www.npmjs.com/package/voz-quiet"}}},
      {"downloads": {"weekly": 420, "monthly": 1800},
       "package": {"name": "voz-slack", "description": "Slack tone", "version": "2.1.0", "publisher": {"username": "bo"}, "links": {"npm": "https://www.npmjs.com/package/voz-slack"}}}
    ]}
    """)

    @Test func sortsByWeeklyDownloads() throws {
        let listings = try PackageListing.decodeSearch(search)
        #expect(listings.map(\.name) == ["voz-slack", "voz-quiet"])
        #expect(listings[0].weeklyDownloads == 420)
        #expect(listings[0].publisher == "bo")
        #expect(listings[0].page?.absoluteString == "https://www.npmjs.com/package/voz-slack")
    }

    @Test func missingDownloadsCountAsZeroAndPlainHttpLinksAreDropped() throws {
        let quiet = try #require(PackageListing.decodeSearch(search).last)
        #expect(quiet.weeklyDownloads == 0)
        #expect(quiet.page == nil)
    }
}
