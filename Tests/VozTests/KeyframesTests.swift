import Testing
@testable import Voz

@Test func rampHoldsAtZeroBeforeItsWindowAndOneAfter() {
    #expect(Keyframes.ramp(0.5, from: 1, to: 2) == 0)
    #expect(Keyframes.ramp(2.5, from: 1, to: 2) == 1)
}

@Test func rampEasesOutInsideItsWindow() {
    let midpoint = Keyframes.ramp(1.5, from: 1, to: 2)
    #expect(midpoint > 0.5)
    #expect(midpoint < 1)
}

@Test func typedRevealsAPrefixOfTheText() {
    #expect(Keyframes.typed("Hello there", progress: 0) == "")
    #expect(Keyframes.typed("Hello there", progress: 0.5) == "Hello")
    #expect(Keyframes.typed("Hello there", progress: 1) == "Hello there")
    #expect(Keyframes.typed("Hello there", progress: 4) == "Hello there")
}

@Test func loopTimeWrapsAtTheLoopDuration() {
    #expect(Keyframes.loopTime(2.5, duration: 2) == 0.5)
    #expect(Keyframes.loopTime(0.25, duration: 2) == 0.25)
}

@Test func fadeEnvelopeHidesTheSceneAtBothEndsOfTheLoop() {
    #expect(Keyframes.fade(0, duration: 6) == 0)
    #expect(Keyframes.fade(3, duration: 6) == 1)
    #expect(Keyframes.fade(6, duration: 6) == 0)
}
