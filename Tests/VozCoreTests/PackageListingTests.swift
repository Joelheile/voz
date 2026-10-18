import Testing
@testable import VozCore

struct PackageListingTests {
    private let search = utf8Data("""
    {"objects": [
      {"package": {"name": "voz-quiet", "version": "1.0.0", "date": "2026-10-01T08:00:00.000Z", "publisher": {"username": "ann"}, "links": {"npm": "http://www.npmjs.com/package/voz-quiet"}}},
      {"downloads": {"weekly": 420, "monthly": 1800},
       "package": {"name": "voz-slack", "description": "Slack tone", "version": "2.1.0", "date": "2026-09-01T08:00:00.000Z", "publisher": {"username": "bo"}, "links": {"npm": "https://www.npmjs.com/package/voz-slack"}}}
    ]}
    """)

    @Test func sortsByMonthlyDownloads() throws {
        let listings = try PackageListing.decodeSearch(search)
        #expect(listings.map(\.name) == ["voz-slack", "voz-quiet"])
        #expect(listings[0].monthlyDownloads == 1800)
        #expect(listings[0].publisher == "bo")
        #expect(listings[0].page?.absoluteString == "https://www.npmjs.com/package/voz-slack")
    }

    @Test func missingDownloadsCountAsZeroAndPlainHttpLinksAreDropped() throws {
        let quiet = try #require(PackageListing.decodeSearch(search).last)
        #expect(quiet.monthlyDownloads == 0)
        #expect(quiet.page == nil)
    }

    @Test func recentPutsTheNewestReleaseFirstAndNameSortsAlphabetically() throws {
        let listings = try PackageListing.decodeSearch(search)
        #expect(listings.ordered(by: .recent).map(\.name) == ["voz-quiet", "voz-slack"])
        #expect(listings.ordered(by: .name).map(\.name) == ["voz-quiet", "voz-slack"])
        #expect(listings.ordered(by: .popular).map(\.name) == ["voz-slack", "voz-quiet"])
    }
}
