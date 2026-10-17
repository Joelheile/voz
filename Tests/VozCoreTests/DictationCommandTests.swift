import Testing
@testable import VozCore

struct DictationCommandTests {
    @Test func toggleStartsWhenIdle() {
        #expect(DictationCommand.command(for: .toggle, in: .idle) == .start(.tap))
        #expect(DictationCommand.command(for: .start, in: .idle) == .start(.hold))
    }

    @Test func toggleAndStopEndRecording() {
        #expect(DictationCommand.command(for: .toggle, in: .recording) == .stop)
        #expect(DictationCommand.command(for: .stop, in: .recording) == .stop)
    }

    @Test func startsWhileTranscribingAreRejected() {
        #expect(DictationCommand.command(for: .toggle, in: .transcribing) == .rejectBusy)
        #expect(DictationCommand.command(for: .start, in: .transcribing) == .rejectBusy)
    }

    @Test func releaseWhileTranscribingIsIgnored() {
        #expect(DictationCommand.command(for: .stop, in: .transcribing) == .ignore)
        #expect(DictationCommand.command(for: .stop, in: .idle) == .ignore)
        #expect(DictationCommand.command(for: .none, in: .recording) == .ignore)
    }
}
