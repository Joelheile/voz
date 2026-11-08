import Testing
@testable import Voz

struct AnalyticsEventTests {
    @Test func boundedFailureCodesExcludeContent() {
        let event = AnalyticsEvent.dictationFailed(stage: .transcription, errorCode: .transcriptionFailed)
        #expect(event.failure?.stage == "transcription")
        #expect(event.failure?.code == "transcription_failed")
        #expect(AnalyticsEvent.appOpened.failure == nil)
        #expect(AppError.appHang.stage == "main_thread")
        #expect(AppError.appHang.rawValue == "app_hang")
        #expect(AppError.accessibilityDenied.stage == "delivery")
        let interrupted = AnalyticsEvent.dictationFailed(stage: .recording, errorCode: .recorderInterrupted)
        #expect(interrupted.failure?.code == "recorder_interrupted")
        #expect(interrupted.properties["os_status"] == nil)
    }

    @Test func recorderFailuresCarryTheSystemStatus() {
        let failed = AnalyticsEvent.dictationFailed(stage: .recording, errorCode: .recorderStartFailed, status: -10868)
        #expect(failed.properties["os_status"] == .integer(-10868))
        #expect(failed.failure?.status == -10868)
    }

    @MainActor
    @Test func hangReportsNameTheCallInProgress() {
        #expect(MainThreadActivity.name == nil)
        MainThreadActivity.during("recorder_start") {
            MainThreadActivity.during("sound_cue") { #expect(MainThreadActivity.name == "sound_cue") }
            #expect(MainThreadActivity.name == "recorder_start")
        }
        #expect(MainThreadActivity.name == nil)
    }

    @Test func theCrashLayerOnlyLetsCrashReportsOut() {
        #expect(CrashReports.allows("$exception", errors: true))
        #expect(!CrashReports.allows("$exception", errors: false))
        #expect(!CrashReports.allows("dictation_completed", errors: true))
    }

    @Test func errorReportsNameTheErrorAndItsCause() {
        let report = CrashReports.exception(stage: "launch", code: "login_item_failed", details: ["cause_domain": "SMAppServiceErrorDomain", "cause_code": 1])
        let entry = (report["$exception_list"] as? [[String: Any]])?.first
        #expect(entry?["type"] as? String == "login_item_failed")
        #expect(entry?["value"] as? String == "login_item_failed cause_code=1 cause_domain=SMAppServiceErrorDomain")
        #expect(report["$exception_fingerprint"] as? String == "voz.launch.login_item_failed")
        #expect(report["cause_domain"] as? String == "SMAppServiceErrorDomain")
    }

    @Test func errorCausesKeepOnlyDomainAndCode() {
        let cause = Analytics.cause(CleanupError.timedOut)
        #expect(cause["cause_domain"] as? String == "Voz.CleanupError")
        #expect(cause.count == 2)
    }

    @Test func crashReportsCarryTheVersionThatCrashed() {
        let crash = CrashReports.stampingAppVersion(["$app_version": "0.0.4"])
        #expect(crash["app_version"] as? String == "0.0.4")
        let usage = CrashReports.stampingAppVersion(["app_version": "0.0.5", "$app_version": "0.0.4"])
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

    @Test func devBuildsNeverUpdateThemselves() {
        #expect(!UpdateChannel.dev.checksInBackground)
        #expect(UpdateChannel.beta.checksInBackground)
        #expect(UpdateChannel.stable.checksInBackground)
    }
}
