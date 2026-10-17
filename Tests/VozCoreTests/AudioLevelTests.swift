import Testing
@testable import VozCore

@Suite struct AudioLevelTests {
    @Test func silenceIsZero() {
        #expect(AudioLevel.normalized(rms: 0) == 0)
        #expect(AudioLevel.normalized(rms: 0.001) == 0)
    }

    @Test func loudSignalIsClampedToOne() {
        #expect(AudioLevel.normalized(rms: 0.5) == 1)
    }

    @Test func midpointDecibelsMapToHalf() {
        let midpointRms = Float(0.0316227766)
        #expect(abs(AudioLevel.normalized(rms: midpointRms) - 0.5) < 0.001)
    }

    @Test func rmsOfSquareWaveIsAmplitude() {
        let samples: [Float] = (0..<1000).map { $0 % 2 == 0 ? 0.2 : -0.2 }
        #expect(abs(AudioLevel.rms(of: samples) - 0.2) < 0.0001)
        #expect(AudioLevel.rms(of: []) == 0)
    }

    @Test func attackIsFasterThanRelease() {
        var rising = LevelSmoother()
        let risen = rising.update(target: 1, elapsedSeconds: 0.04)
        var falling = LevelSmoother()
        _ = falling.update(target: 1, elapsedSeconds: 10)
        let fallen = 1 - falling.update(target: 0, elapsedSeconds: 0.04)
        #expect(risen > fallen)
        #expect(abs(risen - 0.632) < 0.01)
    }

    @Test func smootherConvergesAndHoldsWithoutElapsedTime() {
        var smoother = LevelSmoother()
        #expect(smoother.update(target: 0.8, elapsedSeconds: 0) == 0)
        #expect(abs(smoother.update(target: 0.8, elapsedSeconds: 5) - 0.8) < 0.001)
    }
}
