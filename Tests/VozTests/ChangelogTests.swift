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

    @Test func splitsReleaseNameFromDate() {
        let stable = ChangelogRelease(title: "0.0.5 (October 22, 2026)")
        #expect(stable.name == "0.0.5")
        #expect(stable.date == "October 22, 2026")
        let beta = ChangelogRelease(title: "In beta")
        #expect(beta.name == "In beta")
        #expect(beta.date == nil)
    }
}

@Suite struct OutputModeTests {
    @Test func mapsFlagsToOneChoice() {
        #expect(OutputMode(pastes: true, copies: true) == .both)
        #expect(OutputMode(pastes: true, copies: false) == .type)
        #expect(OutputMode(pastes: false, copies: true) == .copy)
        #expect(OutputMode(pastes: false, copies: false) == .copy)
    }

    @Test func everyChoiceDeliversText() {
        for mode in OutputMode.allCases {
            #expect(mode.pastes || mode.copies)
            #expect(OutputMode(pastes: mode.pastes, copies: mode.copies) == mode)
        }
    }
}
