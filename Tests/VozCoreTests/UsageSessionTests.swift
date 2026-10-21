import Testing
import VozCore

struct UsageSessionTests {
    @Test func reportsOnlyTimeSinceLastCheckpoint() {
        var session = UsageSession(startedAt: 10)
        #expect(session.checkpoint(at: 70) == 60)
        #expect(session.checkpoint(at: 100) == 30)
        #expect(session.checkpoint(at: 100) == 0)
    }

    @Test func boundedFailureCodesExcludeContent() {
        let event = AnalyticsEvent.dictationFailed(stage: .transcription, errorCode: .transcriptionFailed)
        #expect(event.failure?.stage == "transcription")
        #expect(event.failure?.code == "transcription_failed")
        #expect(AnalyticsEvent.appLaunched.failure == nil)
        #expect(AnalyticsEvent.appSession(seconds: 60, state: .heartbeat).properties == ["seconds": .integer(60), "state": .text("heartbeat")])
    }
}
