import Foundation
import GRDB

public struct AppUsage: Equatable, Sendable {
    public let appName: String
    public let words: Int

    public init(appName: String, words: Int) {
        self.appName = appName
        self.words = words
    }
}

public struct DailyWords: Equatable, Sendable, Identifiable {
    public let day: Date
    public let words: Int
    public var id: Date { day }

    public init(day: Date, words: Int) {
        self.day = day
        self.words = words
    }
}

public struct UsageStats: Equatable, Sendable {
    public static let typingWordsPerMinute = 40.0
    public static let seriesDays = 30
    public static let topAppCount = 5

    public var wordsToday = 0
    public var wordsThisWeek = 0
    public var wordsTotal = 0
    public var averageWordsPerMinute: Double?
    public var minutesSaved = 0.0
    public var currentStreak = 0
    public var longestStreak = 0
    public var topApps: [AppUsage] = []
    public var fillerWordsRemoved = 0
    public var dailyWords: [DailyWords] = []

    public init() {}
}

public struct StatsRow: Decodable, FetchableRecord, Sendable {
    public let createdAt: Date
    public let wordCount: Int
    public let audioSeconds: Double
    public let appName: String?
    public let fillerWordsRemoved: Int
}
