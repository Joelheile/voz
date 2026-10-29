import Testing
@testable import Voz

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
        #expect(AnalyticsEvent.appLaunched(byLaunchAgent: false).failure == nil)
        #expect(AppError.appHang.stage == "main_thread")
        #expect(AppError.appHang.rawValue == "app_hang")
        #expect(AppError.accessibilityDenied.stage == "delivery")
        let interrupted = AnalyticsEvent.dictationFailed(stage: .recording, errorCode: .recorderInterrupted)
        #expect(interrupted.failure?.code == "recorder_interrupted")
        #expect(AnalyticsEvent.appSession(seconds: 60, state: .heartbeat).properties == ["seconds": .integer(60), "state": .text("heartbeat")])
    }

    @Test func errorReportsAndUsageFollowTheirOwnSetting() {
        #expect(Analytics.allows("$exception", usage: false, errors: true))
        #expect(!Analytics.allows("dictation_completed", usage: false, errors: true))
        #expect(!Analytics.allows("$exception", usage: true, errors: false))
        #expect(Analytics.allows("dictation_completed", usage: true, errors: false))
    }

    @Test func crashReportsCarryTheVersionThatCrashed() {
        let crash = Analytics.stampingAppVersion(["$app_version": "0.0.4"])
        #expect(crash["app_version"] as? String == "0.0.4")
        let usage = Analytics.stampingAppVersion(["app_version": "0.0.5", "$app_version": "0.0.4"])
        #expect(usage["app_version"] as? String == "0.0.5")
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
}

struct VersionPingQueueTests {
    @Test func retriesKeepPayloadAndAcknowledgementRemovesOnlySentPing() throws {
        let restore = makeVersionPingQueue()
        let queue = try restore()
        let (pingID, pingIDText) = makePingID()
        try queue.enqueue(.install, version: "1.0", previous: nil, pingID: pingID, projectToken: "test")
        let install = try #require(queue.pending.first)
        try queue.enqueue(.update, version: "1.1-beta.4", previous: "1.0", pingID: pingID, projectToken: "test")
        let restored = try restore()
        #expect(restored.pending.first == install)
        let payload = try decodeVersionPing(install)
        #expect(payload.event == "version_ping")
        #expect(!payload.uuid.isEmpty)
        #expect(!payload.timestamp.isEmpty)
        let update = try decodeVersionPing(#require(restored.pending.last))
        #expect(update.distinctID == pingIDText)
        #expect(payload.distinctID == pingIDText)
        #expect(payload.properties.kind == "install")
        #expect(payload.properties.channel == "stable")
        #expect(payload.properties.previous == nil)
        #expect(update.properties.channel == "beta")
        #expect(update.properties.previous == "1.0")
        #expect(!payload.properties.processPersonProfile)
        #expect(payload.properties.geoIPDisable)
        try restored.acknowledge(install)
        #expect(try restore().pending.count == 1)
        try restored.clear()
        #expect(try restore().pending.isEmpty)
    }
}

struct VersionPingKindTests {
    @Test func firstOfficialLaunchIsAnInstallAndAVersionChangeIsAnUpdate() {
        #expect(VersionPing(pingIDIsNew: true, updatedFrom: nil) == .install)
        #expect(VersionPing(pingIDIsNew: false, updatedFrom: "0.0.4") == .update)
        #expect(VersionPing(pingIDIsNew: true, updatedFrom: "0.0.4") == .update)
        #expect(VersionPing(pingIDIsNew: false, updatedFrom: nil) == nil)
    }

    @Test func devBuildsDoNotMakeTheNextOfficialLaunchLookLikeAnUpdate() {
        let launches = recordLaunches(["0.0.5", "0.0.0-dev", "0.0.5"])
        #expect(launches.map(\.updatedFrom) == [nil, nil, nil])
        #expect(recordLaunches(["0.0.4", "0.0.0-dev", "0.0.5"]).last?.updatedFrom == "0.0.4")
    }
}

struct UpdateChannelTests {
    @Test func unstampedBuildsAreDev() {
        #expect(UpdateChannel(version: "0.0.0-dev") == .dev)
        #expect(UpdateChannel(version: "0.0.2-beta.63") == .beta)
        #expect(UpdateChannel(version: "0.0.2") == .stable)
    }
}
