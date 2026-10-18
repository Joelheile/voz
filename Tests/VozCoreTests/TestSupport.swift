import Foundation
import VozCore

@MainActor
final class SettingsFixture {
    private let suiteName = "voz-settings-test-\(UUID().uuidString)"
    private let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    func makeSettings() -> AppSettings {
        AppSettings(defaults: defaults)
    }

    func storedString(forKey key: String) -> String? {
        defaults.string(forKey: key)
    }

    func store(_ value: String, forKey key: String) {
        defaults.set(value, forKey: key)
    }
}

func makeRecord(_ text: String, at seconds: Double = 0) -> TranscriptRecord {
    TranscriptRecord(
        createdAt: Date(timeIntervalSince1970: seconds),
        rawText: text,
        audioSeconds: 2,
        sttMs: 100,
        totalMs: 200,
        model: "parakeet-tdt-v3",
        appBundleID: "com.apple.Notes",
        appName: "Notes"
    )
}

func makeTemporaryStorePath() -> String {
    NSTemporaryDirectory() + "voz-test-\(UUID().uuidString).sqlite"
}

func removeFile(atPath path: String) {
    try? FileManager.default.removeItem(atPath: path)
}

func roundTripThroughJSON(_ hotkey: Hotkey) throws -> Hotkey {
    try JSONDecoder().decode(Hotkey.self, from: JSONEncoder().encode(hotkey))
}

struct DictationEntry {
    var daysAgo = 0
    var hour = 9
    var words = 10
    var seconds = 5.0
    var app: String? = "Notes"
    var fillers = 0
}

enum StatsFixture {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.firstWeekday = 2
        return calendar
    }()

    static let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 18, hour: 15))!

    static func date(daysAgo: Int, hour: Int) -> Date {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now))!
        return calendar.date(byAdding: .hour, value: hour, to: day)!
    }

    static func row(_ entry: DictationEntry) -> StatsRow {
        StatsRow(
            createdAt: date(daysAgo: entry.daysAgo, hour: entry.hour),
            wordCount: entry.words,
            audioSeconds: entry.seconds,
            appName: entry.app,
            fillerWordsRemoved: entry.fillers
        )
    }

    static func stats(_ entries: [DictationEntry]) -> UsageStats {
        var accumulator = StatsAccumulator(now: now, calendar: calendar)
        for entry in entries { accumulator.add(row(entry)) }
        return accumulator.finish()
    }

    static func stats(in store: HistoryStore, entries: [DictationEntry]) throws -> UsageStats {
        for entry in entries {
            var record = makeRecord(String(repeating: "word ", count: entry.words))
            record.createdAt = date(daysAgo: entry.daysAgo, hour: entry.hour)
            record.audioSeconds = entry.seconds
            record.appName = entry.app
            record.fillerWordsRemoved = entry.fillers
            try store.insert(record)
        }
        return try store.stats(now: now, calendar: calendar)
    }
}

func makeCombinationHotkey() -> Hotkey {
    Hotkey(keyCode: 0, modifiers: .maskCommand)
}
