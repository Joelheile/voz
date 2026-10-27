import Testing
@testable import Voz

@MainActor
@Test func audioConfigurationChangeDoesNotWaitForTheMainThread() {
    let recorder = Recorder()
    withExtendedLifetime(recorder) {
        #expect(audioConfigurationChangeReturnsWhileMainThreadIsBlocked())
    }
}
