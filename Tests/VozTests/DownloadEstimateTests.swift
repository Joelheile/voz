import Testing
@testable import Voz

@Suite struct DownloadEstimateTests {
    @Test func showsOnlyThePercentBeforeThereIsEnoughToEstimate() {
        #expect(DownloadEstimate.detail(fraction: 0.01, elapsed: 1) == "1%")
    }

    @Test func projectsTheRemainingTimeFromThePaceSoFar() {
        #expect(DownloadEstimate.detail(fraction: 0.25, elapsed: 40) == "25%, 2 min left")
    }

    @Test func saysUnderAMinuteNearTheEnd() {
        #expect(DownloadEstimate.detail(fraction: 0.9, elapsed: 90) == "90%, under a minute left")
    }
}
