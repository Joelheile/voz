import Foundation
import Synchronization

struct Tally: Codable, Sendable {
    var words = 0
    var dictations = 0
}

/// One fact and the UTC day it belongs to, which becomes its only timestamp
struct DatedFact: Equatable, Sendable {
    let fact: TelemetryFact
    let day: String
}

/// The counters behind every fact. They stay on this Mac until their UTC day ends.
final class TelemetryStore: @unchecked Sendable {
    private struct DayCounters: Codable {
        let day: String
        let week: String
        var words = 0
        var dictations = 0
        var apps: [TelemetryName: Tally] = [:]
        var sites: [TelemetryName: Tally] = [:]
        var latencies: [TelemetryName: [Int]] = [:]
        var failures: [TelemetryName: Int] = [:]
        var extensionRuns: [TelemetryName: Int] = [:]
    }

    private struct State: Codable {
        var isEarlierInstall: Bool
        var firstUseDay: String?
        var lastWeek: String?
        var lastMonth: String?
        var activeDays = 0
        var lastActiveDay: String?
        var totalDictations = 0
        var reached: Set<UsageMilestone> = []
        var waiting: [DatedMilestone] = []
        var today: DayCounters?
        var finished: [DayCounters] = []
    }

    private struct DatedMilestone: Codable {
        let step: UsageMilestone
        let day: String
    }

    static let shared = TelemetryStore()
    private static let key = "telemetryState"
    private static let maxLatenciesPerModel = 500
    private static let maxFinishedDays = 14
    private static let wordRounding = 50
    private static let latencyRounding = 100
    private let defaults: UserDefaults
    private let state: Mutex<State>

    /// Macs that used Voz before this store existed never report install milestones, so old installs don't look like new ones
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = Self.saved(in: defaults)
        let isEarlier = defaults.string(forKey: InstallID.versionPing) != nil || defaults.string(forKey: "lastDailyActivePingDay") != nil
            || defaults.bool(forKey: "onboardingCompleted")
        let initial = saved ?? State(isEarlierInstall: isEarlier)
        state = Mutex(initial)
        Self.save(initial, to: defaults)
    }

    func addDictation(app: TelemetryName, model: TelemetryName, words: Int, totalMs: Int, now: Date) {
        mutate(now) { state, counters in
            counters.words += words
            counters.dictations += 1
            counters.apps[app, default: Tally()].words += words
            counters.apps[app, default: Tally()].dictations += 1
            if counters.latencies[model, default: []].count < Self.maxLatenciesPerModel { counters.latencies[model, default: []].append(totalMs) }
            Self.countProgress(&state, day: counters.day)
        }
    }

    func addSite(_ site: TelemetryName, words: Int, now: Date) {
        mutate(now) { _, counters in
            counters.sites[site, default: Tally()].words += words
            counters.sites[site, default: Tally()].dictations += 1
        }
    }

    /// Any extension counts toward the milestone, and only public npm packages get a named total
    func addExtensionRun(_ package: TelemetryName?, now: Date) {
        mutate(now) { state, counters in
            Self.reach(.firstExtension, in: &state, day: counters.day)
            if let package { counters.extensionRuns[package, default: 0] += 1 }
        }
    }

    func addFailure(_ code: TelemetryName, now: Date) {
        mutate(now) { _, counters in counters.failures[code, default: 0] += 1 }
    }

    func reach(_ step: UsageMilestone, now: Date) {
        mutate(now) { state, counters in Self.reach(step, in: &state, day: counters.day) }
    }

    func clearSites() {
        state.withLock { state in
            state.today?.sites = [:]
            for index in state.finished.indices { state.finished[index].sites = [:] }
            Self.save(state, to: defaults)
        }
    }

    /// What's ready to send: milestones reached so far and every counter from a day that has ended.
    /// `weeklyDay` is set when a reported day is the first active one of its week, which is when the weekly facts go.
    func takeReady(now: Date) -> (facts: [DatedFact], weeklyDay: String?) {
        state.withLock { state in
            Self.finishToday(&state, ifNotOn: Self.day(of: now))
            var facts = state.waiting.map { DatedFact(fact: .milestone($0.step), day: $0.day) }
            var weeklyDay: String?
            for counters in state.finished {
                let isActive = counters.dictations > 0
                let firstOfMonth = Self.claim(String(counters.day.prefix(7)), in: &state.lastMonth, active: isActive)
                let firstOfWeek = Self.claim(counters.week, in: &state.lastWeek, active: isActive)
                if firstOfWeek { weeklyDay = counters.day }
                facts += Self.report(counters, state: state, firstOfWeek: firstOfWeek, firstOfMonth: firstOfMonth)
            }
            state.waiting = []
            state.finished = []
            Self.save(state, to: defaults)
            return (facts, weeklyDay)
        }
    }

    /// What goes out when these days end, for `voz telemetry`
    func held() -> [TelemetryFact] {
        state.withLock { state in
            (state.finished + [state.today].compactMap(\.self)).flatMap { counters in
                Self.report(counters, state: state, firstOfWeek: false, firstOfMonth: false).map(\.fact)
            }
        }
    }

    static func day(of date: Date) -> String {
        date.ISO8601Format(.iso8601.year().month().day())
    }

    /// Rounded totals still add up across installs, and they say less than an exact count
    private static func rounded(_ value: Int, to step: Int) -> Int {
        (value + step / 2) / step * step
    }

    static func ageBucket(weeks: Int) -> String {
        switch weeks {
        case ..<4: String(max(weeks, 0))
        case 4..<8: "4-7"
        case 8..<16: "8-15"
        default: "16+"
        }
    }

    private func mutate(_ now: Date, _ change: (inout State, inout DayCounters) -> Void) {
        state.withLock { state in
            let day = Self.day(of: now)
            Self.finishToday(&state, ifNotOn: day)
            var counters = state.today ?? DayCounters(day: day, week: Self.week(of: now))
            change(&state, &counters)
            state.today = counters
            Self.save(state, to: defaults)
        }
    }

    /// An ended day waits here until it's reported, so a new day's first use can't lose it
    private static func finishToday(_ state: inout State, ifNotOn day: String) {
        guard let today = state.today, today.day != day else { return }
        state.finished = Array((state.finished + [today]).suffix(maxFinishedDays))
        state.today = nil
    }

    private static func countProgress(_ state: inout State, day: String) {
        if state.firstUseDay == nil, !state.isEarlierInstall { state.firstUseDay = day }
        state.totalDictations += 1
        if state.lastActiveDay != day {
            state.lastActiveDay = day
            state.activeDays += 1
        }
        let progress: [(Bool, UsageMilestone)] = [
            (state.totalDictations >= 1, .firstDictation), (state.totalDictations >= 10, .dictations10), (state.totalDictations >= 100, .dictations100),
            (state.activeDays >= 2, .activeDays2), (state.activeDays >= 7, .activeDays7), (state.activeDays >= 30, .activeDays30),
        ]
        for (isReached, step) in progress where isReached { reach(step, in: &state, day: day) }
    }

    private static func reach(_ step: UsageMilestone, in state: inout State, day: String) {
        guard !state.isEarlierInstall, state.reached.insert(step).inserted else { return }
        state.waiting.append(DatedMilestone(step: step, day: day))
    }

    private static func claim(_ period: String, in last: inout String?, active: Bool) -> Bool {
        guard active, last != period else { return false }
        last = period
        return true
    }

    private static func report(_ counters: DayCounters, state: State, firstOfWeek: Bool, firstOfMonth: Bool) -> [DatedFact] {
        var facts: [TelemetryFact] = []
        if counters.dictations > 0 {
            facts.append(.dailyActive(
                firstOfWeek: firstOfWeek,
                firstOfMonth: firstOfMonth,
                weeksSinceFirstUse: weeksSinceFirstUse(on: counters.day, firstUseDay: state.firstUseDay),
                words: rounded(counters.words, to: wordRounding),
                dictations: counters.dictations
            ))
        }
        facts += counters.apps.map { .appDay($0.key, words: rounded($0.value.words, to: wordRounding), dictations: $0.value.dictations) }
        facts += counters.sites.map { .siteDay($0.key, words: rounded($0.value.words, to: wordRounding), dictations: $0.value.dictations) }
        facts += counters.latencies.map { .latencyDay(model: $0.key, medianMs: rounded(median($0.value), to: latencyRounding), dictations: $0.value.count) }
        facts += counters.failures.map { .failureDay($0.key, count: $0.value) }
        facts += counters.extensionRuns.map { .extensionDay(package: $0.key, runs: $0.value) }
        return facts.map { DatedFact(fact: $0, day: counters.day) }
    }

    private static func weeksSinceFirstUse(on day: String, firstUseDay: String?) -> String {
        guard let firstUseDay, let start = date(of: firstUseDay), let end = date(of: day) else { return "earlier" }
        return ageBucket(weeks: Int(end.timeIntervalSince(start) / (7 * 24 * 3600)))
    }

    private static func median(_ values: [Int]) -> Int {
        values.sorted()[values.count / 2]
    }

    private static func date(of day: String) -> Date? {
        ISO8601DateFormatter().date(from: "\(day)T00:00:00Z")
    }

    private static func week(of date: Date) -> String {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .gmt
        let week = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return "\(week.yearForWeekOfYear ?? 0)-\(week.weekOfYear ?? 0)"
    }

    private static func saved(in defaults: UserDefaults) -> State? {
        guard let data = defaults.data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode(State.self, from: data)
        } catch {
            Log.app.error("Could not read telemetry counters: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func save(_ state: State, to defaults: UserDefaults) {
        do {
            defaults.set(try JSONEncoder().encode(state), forKey: key)
        } catch {
            Log.app.error("Could not save telemetry counters: \(error.localizedDescription, privacy: .public)")
        }
    }
}
