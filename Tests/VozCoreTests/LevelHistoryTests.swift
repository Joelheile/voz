import Testing
@testable import VozCore

struct LevelHistoryTests {
    @Test func emptyHistoryIsSilent() {
        #expect(LevelHistory().level(at: 10) == 0)
    }

    @Test func interpolatesBetweenSamples() {
        var history = LevelHistory()
        history.append(0, at: 1)
        history.append(1, at: 2)
        #expect(history.level(at: 1.25) == 0.25)
    }

    @Test func holdsTheNewestLevelAfterTheLastSample() {
        var history = LevelHistory()
        history.append(0.2, at: 1)
        history.append(0.8, at: 2)
        #expect(history.level(at: 5) == 0.8)
        #expect(history.latest == 0.8)
    }

    @Test func isSilentBeforeTheFirstSample() {
        var history = LevelHistory()
        history.append(0.5, at: 1)
        #expect(history.level(at: 0.5) == 0)
    }

    @Test func forgetsSamplesBeyondCapacity() {
        var history = LevelHistory()
        for step in 0...LevelHistory.capacity {
            history.append(1, at: Double(step))
        }
        #expect(history.level(at: 0) == 0)
        #expect(history.level(at: 1) == 1)
    }

    @Test func resetClearsSamples() {
        var history = LevelHistory()
        history.append(1, at: 1)
        history.reset()
        #expect(history.level(at: 1) == 0)
    }
}
