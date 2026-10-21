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

    @Test func extensionEventsNameOnlyPublicNpmPackages() {
        let npm = AnalyticsEvent.extensionChanged(change: .install, source: .npm(name: "voz-mail", spec: "voz-mail"))
        #expect(npm.name == "extension_installed")
        #expect(npm.properties == ["source": .text("npm"), "package": .text("voz-mail")])
        let git = AnalyticsEvent.extensionFailed(change: .update, source: .git(host: "github.com", path: "me/private", ref: nil), failure: .bunDownload)
        #expect(git.name == "extension_failed")
        #expect(git.properties == ["source": .text("git"), "change": .text("update"), "error_code": .text("bun_download_failed")])
        #expect(git.failure?.stage == "extension_update")
        let local = AnalyticsEvent.extensionChanged(change: .remove, source: localSource("/Users/me/secret"))
        #expect(local.properties == ["source": .text("local")])
    }

    @Test func setupEventsReportStepAndOutcome() {
        #expect(AnalyticsEvent.setupStepViewed(.tryIt).properties == ["step": .text("try_it")])
        let completed = AnalyticsEvent.setupCompleted(allPermissionsGranted: false, triedDictation: true)
        #expect(completed.name == "setup_completed")
        #expect(completed.properties == ["all_permissions_granted": .flag(false), "tried_dictation": .flag(true)])
    }
}
