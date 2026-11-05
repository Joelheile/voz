import Testing
@testable import Voz

private let slack = "com.tinyspeck.slackmacgap"
private let friday = "2026-10-30"

private func dictate(_ store: TelemetryStore, at time: String, words: Int = 10, app: String = slack, totalMs: Int = 500) {
    store.addDictation(app: .app(app), model: .model("parakeet-ultra"), words: words, totalMs: totalMs, now: utcDate(time))
}

private func dailyActive(in facts: [DatedFact]) -> [(firstOfWeek: Bool, firstOfMonth: Bool, age: String, words: Int, dictations: Int, day: String)] {
    facts.compactMap { dated in
        guard case let .dailyActive(week, month, age, words, dictations) = dated.fact else { return nil }
        return (week, month, age, words, dictations, dated.day)
    }
}

private func milestones(in facts: [DatedFact]) -> [UsageMilestone] {
    facts.compactMap { if case let .milestone(step) = $0.fact { step } else { nil } }
}

struct TelemetryStoreTests {
    @Test func holdsCountersUntilTheDayEndsThenReportsRoundedTotals() {
        let store = TelemetryStore(defaults: makeDefaults())
        dictate(store, at: "\(friday)T09:00:00Z", words: 40)
        dictate(store, at: "\(friday)T10:00:00Z", words: 30, app: "com.example.unlisted")
        #expect(store.takeReady(now: utcDate("\(friday)T23:00:00Z")).facts.allSatisfy { if case .milestone = $0.fact { true } else { false } })

        let facts = store.takeReady(now: utcDate("2026-10-31T00:01:00Z")).facts
        let active = dailyActive(in: facts)
        #expect(active.count == 1)
        #expect(active.first?.words == 50)
        #expect(active.first?.dictations == 2)
        #expect(active.first?.day == friday)
        #expect(facts.contains { $0.fact == .appDay(.app(slack), words: 50, dictations: 1) })
        #expect(facts.contains { $0.fact == .appDay(.app(nil), words: 50, dictations: 1) })
        #expect(facts.contains { $0.fact == .latencyDay(model: .model("parakeet-ultra"), medianMs: 500, dictations: 2) })
        #expect(store.takeReady(now: utcDate("2026-10-31T00:02:00Z")).facts.isEmpty)
    }

    @Test func aNewDaysFirstUseKeepsTheUnreportedDay() {
        let store = TelemetryStore(defaults: makeDefaults())
        dictate(store, at: "\(friday)T09:00:00Z")
        dictate(store, at: "2026-10-31T09:00:00Z")
        dictate(store, at: "2026-11-01T09:00:00Z")
        let days = dailyActive(in: store.takeReady(now: utcDate("2026-11-02T09:00:00Z")).facts).map(\.day)
        #expect(days == [friday, "2026-10-31", "2026-11-01"])
    }

    @Test func aLaunchReportsADayWithoutAnotherDictation() {
        let defaults = makeDefaults()
        dictate(TelemetryStore(defaults: defaults), at: "\(friday)T09:00:00Z")
        let restarted = TelemetryStore(defaults: defaults)
        #expect(dailyActive(in: restarted.takeReady(now: utcDate("2026-11-20T09:00:00Z")).facts).count == 1)
    }

    @Test func flagsTheFirstActiveDayOfEachWeekAndMonth() {
        let store = TelemetryStore(defaults: makeDefaults())
        func report(_ day: String) -> (Bool?, Bool?, String?) {
            dictate(store, at: "\(day)T12:00:00Z")
            let ready = store.takeReady(now: utcDate("\(day)T12:00:00Z").addingTimeInterval(86400))
            let active = dailyActive(in: ready.facts).first
            return (active?.firstOfWeek, active?.firstOfMonth, ready.weeklyDay)
        }
        let first = report(friday)
        #expect(first.0 == true && first.1 == true && first.2 == friday)
        let sameWeek = report("2026-10-31")
        #expect(sameWeek.0 == false && sameWeek.1 == false && sameWeek.2 == nil)
        let nextMonth = report("2026-11-01")
        #expect(nextMonth.0 == false && nextMonth.1 == true)
        let nextWeek = report("2026-11-02")
        #expect(nextWeek.0 == true && nextWeek.1 == false && nextWeek.2 == "2026-11-02")
    }

    @Test func aDayWithOnlyFailuresDoesNotCountAsActive() {
        let store = TelemetryStore(defaults: makeDefaults())
        store.addFailure(.failure(.appHang), now: utcDate("\(friday)T09:00:00Z"))
        let ready = store.takeReady(now: utcDate("2026-10-31T09:00:00Z"))
        #expect(dailyActive(in: ready.facts).isEmpty)
        #expect(ready.weeklyDay == nil)
        #expect(ready.facts.map(\.fact) == [.failureDay(.failure(.appHang), count: 1)])
    }

    @Test func reportsHowManyWeeksAgoSomeoneStarted() {
        let store = TelemetryStore(defaults: makeDefaults())
        dictate(store, at: "\(friday)T09:00:00Z")
        _ = store.takeReady(now: utcDate("2026-10-31T09:00:00Z"))
        dictate(store, at: "2026-11-13T09:00:00Z")
        #expect(dailyActive(in: store.takeReady(now: utcDate("2026-11-14T09:00:00Z")).facts).first?.age == "2")
        #expect(TelemetryStore.ageBucket(weeks: 3) == "3")
        #expect(TelemetryStore.ageBucket(weeks: 4) == "4-7")
        #expect(TelemetryStore.ageBucket(weeks: 15) == "8-15")
        #expect(TelemetryStore.ageBucket(weeks: 16) == "16+")
    }

    @Test func eachMilestoneCountsOncePerInstall() {
        let store = TelemetryStore(defaults: makeDefaults())
        for _ in 1...10 { dictate(store, at: "\(friday)T09:00:00Z") }
        store.reach(.setupAccess, now: utcDate("\(friday)T09:00:00Z"))
        store.reach(.setupAccess, now: utcDate("\(friday)T09:00:00Z"))
        let first = milestones(in: store.takeReady(now: utcDate("\(friday)T10:00:00Z")).facts)
        #expect(Set(first) == [.firstDictation, .dictations10, .setupAccess])
        #expect(first.count == 3)
        dictate(store, at: "2026-10-31T09:00:00Z")
        #expect(milestones(in: store.takeReady(now: utcDate("2026-10-31T10:00:00Z")).facts) == [.activeDays2])
    }

    @Test(arguments: [InstallID.versionPing, "lastDailyActivePingDay"])
    func installsFromBeforeThisStoreDontLookNew(marker: String) {
        let defaults = makeDefaults()
        defaults.set("seen", forKey: marker)
        let store = TelemetryStore(defaults: defaults)
        dictate(store, at: "\(friday)T09:00:00Z")
        let facts = store.takeReady(now: utcDate("2026-10-31T09:00:00Z")).facts
        #expect(milestones(in: facts).isEmpty)
        #expect(dailyActive(in: facts).first?.age == "earlier")
    }

    @Test func clearingSitesRemovesThemFromEveryDayStillHeld() {
        let store = TelemetryStore(defaults: makeDefaults())
        store.addSite(.site("github.com"), words: 100, now: utcDate("\(friday)T09:00:00Z"))
        store.addSite(.site("github.com"), words: 100, now: utcDate("2026-10-31T09:00:00Z"))
        #expect(store.held().filter(\.isLinked).count == 2)
        store.clearSites()
        #expect(store.held().filter(\.isLinked).isEmpty)
    }

    @Test func aMedianHidesASingleSlowDictation() {
        let store = TelemetryStore(defaults: makeDefaults())
        for totalMs in [420, 460, 90000] { dictate(store, at: "\(friday)T09:00:00Z", totalMs: totalMs) }
        let facts = store.takeReady(now: utcDate("2026-10-31T09:00:00Z")).facts.map(\.fact)
        #expect(facts.contains(.latencyDay(model: .model("parakeet-ultra"), medianMs: 500, dictations: 3)))
    }

    @Test func anyExtensionReachesTheMilestoneButOnlyNamedOnesAreCounted() {
        let store = TelemetryStore(defaults: makeDefaults())
        store.addExtensionRun(nil, now: utcDate("\(friday)T09:00:00Z"))
        let facts = store.takeReady(now: utcDate("2026-10-31T09:00:00Z")).facts
        #expect(milestones(in: facts) == [.firstExtension])
        #expect(facts.count == 1)
    }
}

struct TelemetryNameTests {
    @Test func unlistedAppsAndSitesBecomeOther() {
        #expect(TelemetryName.app(slack).value == "slack")
        #expect(TelemetryName.app("com.bank.secret").value == UsageKeys.other)
        #expect(TelemetryName.app(nil).value == UsageKeys.other)
        #expect(TelemetryName.site("www.mybank.com").value == UsageKeys.other)
    }

    @Test func aSubdomainMatchesItsListedSite() {
        #expect(TelemetryName.site("www.github.com").value == "github")
        #expect(TelemetryName.site("mail.google.com").value == "gmail")
        #expect(TelemetryName.site("google.com").value == UsageKeys.other)
        #expect(TelemetryName.site("github.com.evil.example").value == UsageKeys.other)
    }

    @Test func extensionsAreNamedOnlyWhenPublic() {
        let installed = [
            InstalledExtension(name: "voz-mail", source: .npm(name: "voz-mail", spec: "voz-mail@1.0.0")),
            InstalledExtension(name: "private", source: .git(host: "github.com", path: "me/private", ref: nil)),
            InstalledExtension(name: "loose", source: nil),
        ]
        #expect(TelemetryName.package(named: "voz-mail", in: installed)?.value == "voz-mail")
        #expect(TelemetryName.package(named: "private", in: installed) == nil)
        #expect(TelemetryName.package(named: "loose", in: installed) == nil)
        #expect(TelemetryName.package(named: "missing", in: installed) == nil)
    }

    @Test func chipsAreReducedToAFamily() {
        #expect(TelemetryEnvironment.chipFamily(of: "Apple M3 Pro") == "m3")
        #expect(TelemetryEnvironment.chipFamily(of: "Apple M1") == "m1")
        #expect(TelemetryEnvironment.chipFamily(of: "Intel(R) Core(TM) i9") == "other")
    }
}

struct TelemetryEventTests {
    @Test func setupStepsAndGrantedPermissionsBecomeMilestones() {
        #expect(AnalyticsEvent.setupStepViewed(.tryIt).milestone == .setupTryIt)
        #expect(AnalyticsEvent.setupCompleted(allPermissionsGranted: false, triedDictation: false).milestone == .setupCompleted)
        #expect(AnalyticsEvent.permissionResult(permission: .microphone, granted: true).milestone == .permissionMicrophone)
        #expect(AnalyticsEvent.permissionResult(permission: .microphone, granted: false).milestone == nil)
        #expect(AnalyticsEvent.historyOpened.milestone == nil)
    }

    @Test func failuresAndDiscardsCountUnderFixedCodes() {
        #expect(AnalyticsEvent.dictationFailed(stage: .recording, errorCode: .recorderInterrupted).countedFailure?.value == "recorder_interrupted")
        #expect(AnalyticsEvent.dictationDiscarded(reason: .silent).countedFailure?.value == "discarded_silent")
        #expect(AnalyticsEvent.modelFailed(model: .parakeetUltra).countedFailure?.value == "model_load_failed")
        #expect(AnalyticsEvent.historyOpened.countedFailure == nil)
    }

    @Test func factsCarryNoLinkingIDAndOnlyTheirDay() throws {
        let environment = TelemetryEnvironment(version: "0.2.0", channel: "stable", osMajor: 26, chipFamily: "m3")
        let fact = DatedFact(fact: .appDay(.app(slack), words: 50, dictations: 1), day: friday)
        let installID = newInstallID()
        let first = try payloadFields(TelemetryPayload.body(fact, installID: installID, environment: environment))
        let second = try payloadFields(TelemetryPayload.body(fact, installID: installID, environment: environment))
        #expect(first.id != second.id)
        #expect(first.id != installID.uuidString)
        #expect(first.timestamp == "\(friday)T00:00:00Z")
        #expect(first.personProfile == false)
        #expect(first.geoIP == true)
    }

    @Test func onlySiteTotalsUseTheInstallID() throws {
        let environment = TelemetryEnvironment(version: "0.2.0", channel: "stable", osMajor: 26, chipFamily: "m3")
        let installID = newInstallID()
        for sample in TelemetryFact.samples {
            let fields = try payloadFields(TelemetryPayload.body(DatedFact(fact: sample, day: friday), installID: installID, environment: environment))
            let usesInstallID = fields.id == installID.uuidString
            #expect(usesInstallID == (sample.name == "site_day"), "\(sample.name)")
        }
    }

    @Test func optInEventsKeepTheirIDAndRealTime() throws {
        let installID = newInstallID()
        let now = utcDate("\(friday)T09:30:15Z")
        let fields = try payloadFields(Analytics.body(for: .historyOpened, installID: installID, now: now))
        #expect(fields.id == installID.uuidString)
        #expect(fields.timestamp == "\(friday)T09:30:15Z")
    }
}

@MainActor
struct TelemetrySenderTests {
    @Test func aRejectedEventStaysQueuedAndCantHoldUpTheRest() async throws {
        let server = FakeTelemetryServer(accepts: [false, true, true])
        let defaults = makeDefaults()
        let sender = server.sender(defaults: defaults)
        sender.send(try ["first", "second"].map(testEventBody))
        await sender.finishSending()
        #expect(server.events.count == 3)
        #expect(Set(server.events) == ["first", "second"])
        #expect(sender.pending.isEmpty)
        #expect(server.waits == [.seconds(600)])
    }

    @Test func aQueueSurvivesAQuit() async throws {
        let defaults = makeDefaults()
        let server = FakeTelemetryServer(accepts: [false])
        let sender = server.sender(defaults: defaults)
        sender.send([try testEventBody("first")])
        #expect(TelemetrySender.queuedEvents(in: defaults) == ["first"])
        let restarted = FakeTelemetryServer().sender(defaults: defaults)
        #expect(restarted.pending.count == 1)
    }

    @Test func anonymousEventsWaitBeforeEachSend() async throws {
        let server = FakeTelemetryServer()
        let sender = server.sender(spacingSeconds: 30...120, defaults: makeDefaults())
        sender.send(try ["first", "second", "third"].map(testEventBody))
        await sender.finishSending()
        #expect(server.waits.count == 3)
        #expect(server.waits.allSatisfy { $0 >= .seconds(30) && $0 <= .seconds(120) })
    }

    @Test func clearingDuringASendKeepsTheEventGone() async throws {
        let defaults = makeDefaults()
        let cleared = ClearOnFirstPost()
        let server = FakeTelemetryServer(accepts: [false]) { await cleared.run() }
        let sender = server.sender(key: TelemetrySender.usageKey, defaults: defaults)
        cleared.action = { sender.clear() }
        sender.send([try testEventBody("first")])
        await sender.finishSending()
        #expect(sender.pending.isEmpty)
        #expect(TelemetrySender.queuedEvents(in: defaults).isEmpty)
    }

    @Test func theQueueKeepsOnlyTheNewestEvents() throws {
        let sender = FakeTelemetryServer(accepts: Array(repeating: false, count: 1)).sender(defaults: makeDefaults())
        sender.send(try (0..<600).map { try testEventBody("event\($0)") })
        #expect(sender.pending.count == 500)
    }
}

@MainActor
private final class ClearOnFirstPost {
    var action: (() -> Void)?

    func run() {
        action?()
    }
}

@MainActor
struct TelemetryReporterTests {
    private final class Clock {
        var now = utcDate("\(friday)T09:00:00Z")
    }

    private struct Setup {
        let reporter: TelemetryReporter
        let settings: AppSettings
        let store: TelemetryStore
        let server: FakeTelemetryServer
        let sender: TelemetrySender
        let clock: Clock
    }

    private func makeReporter(isPublicWindow: @escaping @MainActor (HostApp) async -> Bool = { _ in true }) -> Setup {
        let defaults = makeDefaults()
        let home = temporaryHome()
        let settings = AppSettings(defaults: makeDefaults(), home: home)
        let store = TelemetryStore(defaults: defaults)
        let server = FakeTelemetryServer()
        let sender = server.sender(defaults: defaults)
        let clock = Clock()
        let reporter = TelemetryReporter(
            settings: settings,
            analytics: Analytics(usage: false, errors: false, installID: newInstallID()),
            store: store,
            sender: sender,
            home: home,
            defaults: defaults,
            isActive: true,
            environment: TelemetryEnvironment(version: "0.2.0", channel: "stable", osMajor: 26, chipFamily: "m3"),
            now: { clock.now },
            isPublicWindow: isPublicWindow
        )
        return Setup(reporter: reporter, settings: settings, store: store, server: server, sender: sender, clock: clock)
    }

    @Test func aFinishedDaySendsItsFactsUnlinked() async {
        let setup = makeReporter()
        setup.reporter.recordDictation(app: HostApp(bundleID: slack, name: "Slack"), model: "parakeet-ultra", words: 60, totalMs: 500)
        setup.clock.now = utcDate("2026-10-31T09:00:00Z")
        setup.reporter.report()
        await setup.sender.finishSending()
        let events = Set(setup.server.events)
        #expect(events.isSuperset(of: ["milestone", "daily_active", "app_day", "latency_day", "settings_week"]))
        #expect(Set(setup.server.ids).count == setup.server.ids.count)
        #expect(setup.server.timestamps.allSatisfy { $0.hasPrefix(friday) })
        #expect(!events.contains("site_day"))
    }

    @Test func aFirstLaunchPingsOnceAndAnUpdatePingsAgain() async {
        let setup = makeReporter()
        setup.reporter.start(launch: LaunchVersion(current: "0.2.0", updatedFrom: nil))
        setup.reporter.start(launch: LaunchVersion(current: "0.2.0", updatedFrom: nil))
        await setup.sender.finishSending()
        #expect(setup.server.events == ["version_ping"])
        setup.reporter.start(launch: LaunchVersion(current: "0.3.0", updatedFrom: "0.2.0"))
        await setup.sender.finishSending()
        #expect(setup.server.events == ["version_ping", "version_ping"])
    }

    @Test func sitesCountOnlyWithTheOptInAndAPublicWindow() async {
        let app = HostApp(bundleID: "com.apple.Safari", name: "Safari", website: "github.com")
        let optedOut = makeReporter()
        await optedOut.reporter.recordSite(of: app, words: 100)
        #expect(optedOut.store.held().isEmpty)

        let privateWindow = makeReporter { _ in false }
        privateWindow.settings.analyticsEnabled = true
        await privateWindow.reporter.recordSite(of: app, words: 100)
        #expect(privateWindow.store.held().isEmpty)

        let optedIn = makeReporter()
        optedIn.settings.analyticsEnabled = true
        await optedIn.reporter.recordSite(of: app, words: 100)
        #expect(optedIn.store.held() == [.siteDay(.site("github.com"), words: 100, dictations: 1)])
    }
}
