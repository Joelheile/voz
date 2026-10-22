import Foundation
import GRDB

public enum StatsPeriod: String, CaseIterable, Sendable {
    case day = "Today"
    case week = "7 days"
    case month = "30 days"
    case all = "All time"
}

public struct WordBucket: Equatable, Sendable, Identifiable {
    public let start: Date
    public let words: Int
    public var id: Date { start }

    public init(start: Date, words: Int) {
        self.start = start
        self.words = words
    }
}

public struct AppUsage: Hashable, Sendable {
    public let bundleID: String?
    public let name: String
    public let words: Int

    public init(bundleID: String?, name: String, words: Int) {
        self.bundleID = bundleID
        self.name = name
        self.words = words
    }
}

public struct PeriodStats: Equatable, Sendable {
    public var words = 0
    public var speakingSeconds = 0.0
    public var fixes = 0
    public var wordsPerMinute: Double?
    public var buckets: [WordBucket] = []
    public var topApps: [AppUsage] = []

    public init() {}
}

public struct UsageStats: Equatable, Sendable {
    public var periods: [StatsPeriod: PeriodStats] = [:]

    public init() {}

    public subscript(period: StatsPeriod) -> PeriodStats {
        periods[period] ?? PeriodStats()
    }
}

public struct StatsRow: Decodable, FetchableRecord, Sendable {
    public let createdAt: Date
    public let wordCount: Int
    public let audioSeconds: Double
    public let fillerWordsRemoved: Int
    public let appBundleID: String?
    public let appName: String?
}
