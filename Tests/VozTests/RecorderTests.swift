import Testing
@testable import Voz

@MainActor
@Test func audioConfigurationChangeDoesNotWaitForTheMainThread() {
    let recorder = Recorder()
    withExtendedLifetime(recorder) {
        #expect(audioConfigurationChangeReturnsWhileMainThreadIsBlocked())
    }
}

private struct EngineRefused: Error {}

@MainActor
@Test func preparedEngineThatRefusesToStartIsReplacedByAFreshOne() throws {
    var attempts: [String] = []
    let started = try Recorder.startCapture(prepared: "prepared", fresh: { "fresh" }) { capture in
        attempts.append(capture)
        if capture == "prepared" { throw EngineRefused() }
    }
    #expect(started == "fresh")
    #expect(attempts == ["prepared", "fresh"])
}

@MainActor
@Test func freshEngineFailureStillReachesTheCaller() {
    var attempts = 0
    #expect(throws: EngineRefused.self) {
        try Recorder.startCapture(prepared: nil as String?, fresh: { "fresh" }) { _ in
            attempts += 1
            throw EngineRefused()
        }
    }
    #expect(attempts == 1)
}
