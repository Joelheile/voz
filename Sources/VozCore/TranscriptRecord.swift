import Foundation
import GRDB

public struct TranscriptRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable, Sendable {
    public static let databaseTableName = "transcript"

    public var id: UUID
    public var createdAt: Date
    public var rawText: String
    public var finalText: String
    public var audioSeconds: Double
    public var wordCount: Int
    public var sttMs: Int
    public var totalMs: Int
    public var model: String
    public var appBundleID: String?
    public var appName: String?
    public var fillerWordsRemoved: Int
    public var cleanupMs: Int
    public var cleanupTimedOut: Bool

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        rawText: String,
        finalText: String? = nil,
        audioSeconds: Double,
        sttMs: Int,
        totalMs: Int,
        model: String,
        appBundleID: String?,
        appName: String?,
        fillerWordsRemoved: Int = 0,
        cleanupMs: Int = 0,
        cleanupTimedOut: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.rawText = rawText
        self.finalText = finalText ?? rawText
        self.audioSeconds = audioSeconds
        self.wordCount = (finalText ?? rawText).split(whereSeparator: \.isWhitespace).count
        self.sttMs = sttMs
        self.totalMs = totalMs
        self.model = model
        self.appBundleID = appBundleID
        self.appName = appName
        self.fillerWordsRemoved = fillerWordsRemoved
        self.cleanupMs = cleanupMs
        self.cleanupTimedOut = cleanupTimedOut
    }
}
