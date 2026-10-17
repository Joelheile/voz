import Testing
@testable import VozCore

@Suite struct CleanupBudgetTests {
    @Test func totalBudgetIsOneAndAHalfSeconds() {
        #expect(CleanupBudget.total == .milliseconds(1500))
    }

    @Test func scalesTokenCapWithWords() {
        #expect(CleanupBudget.maxResponseTokens(forWords: 10) == 78)
    }

    @Test func capsTokenCap() {
        #expect(CleanupBudget.maxResponseTokens(forWords: 1000) == 512)
    }

    @Test func convertsDurationToWholeMilliseconds() {
        #expect(Duration.milliseconds(1234).wholeMilliseconds == 1234)
        #expect(Duration.seconds(2).wholeMilliseconds == 2000)
    }
}
