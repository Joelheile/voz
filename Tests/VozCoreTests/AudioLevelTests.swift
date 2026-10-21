import Testing
@testable import VozCore

struct AudioLevelTests {
    @Test func rmsOfEmptySamplesIsZero() {
        #expect(AudioLevel.rms(of: []) == 0)
    }

    @Test func rmsOfConstantSignalIsItsMagnitude() {
        #expect(abs(AudioLevel.rms(of: [0.5, -0.5, 0.5, -0.5]) - 0.5) < 1e-6)
    }

    @Test func smootherRisesFasterThanItFalls() {
        var rising = LevelSmoother()
        let up = rising.update(target: 1, elapsedSeconds: 0.02)
        var falling = LevelSmoother()
        _ = falling.update(target: 1, elapsedSeconds: 10)
        let down = 1 - falling.update(target: 0, elapsedSeconds: 0.02)
        #expect(up > down)
    }

    @Test func smootherIgnoresNegativeElapsedTime() {
        var smoother = LevelSmoother()
        #expect(smoother.update(target: 1, elapsedSeconds: -1) == 0)
    }
}
