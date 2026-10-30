import Testing
@testable import Voz

@Suite struct ChangelogTests {
    @Test func groupsBulletsUnderEachReleaseHeading() {
        let markdown = """
        # What's new in Voz

        Newest first.

        ## In beta

        - Text appears sooner
        - Long notifications show in full

        ## 0.0.5 (October 22, 2026)

        - Calmer settings
        """
        #expect(Changelog.parse(markdown) == [
            ChangelogRelease(title: "In beta", changes: ["Text appears sooner", "Long notifications show in full"]),
            ChangelogRelease(title: "0.0.5 (October 22, 2026)", changes: ["Calmer settings"]),
        ])
    }
}
