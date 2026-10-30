import Combine
import Foundation
import GRDB

final class HistoryStore: Sendable {
    static let menuLimit = 10
    static let searchLimit = 100

    private static let containsIgnoringCase = DatabaseFunction("contains_ignoring_case", argumentCount: 2, pure: true) { values in
        guard let haystack = String.fromDatabaseValue(values[0]), let needle = String.fromDatabaseValue(values[1]) else {
            return nil
        }
        return haystack.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private let queue: DatabaseQueue
    let vocabulary: VocabularyStore

    init(path: String? = nil) throws {
        var configuration = Configuration()
        configuration.prepareDatabase { database in
            database.add(function: Self.containsIgnoringCase)
        }
        queue = try path.map { try DatabaseQueue(path: $0, configuration: configuration) }
            ?? DatabaseQueue(configuration: configuration)
        try Self.migrator.migrate(queue)
        vocabulary = VocabularyStore(queue: queue)
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { database in
            try database.create(table: TranscriptRecord.databaseTableName) { table in
                table.primaryKey("id", .blob)
                table.column("createdAt", .datetime).notNull().indexed()
                table.column("rawText", .text).notNull()
                table.column("finalText", .text).notNull()
                table.column("audioSeconds", .double).notNull()
                table.column("wordCount", .integer).notNull()
                table.column("sttMs", .integer).notNull()
                table.column("totalMs", .integer).notNull()
                table.column("model", .text).notNull()
                table.column("appBundleID", .text)
                table.column("appName", .text)
                table.column("fillerWordsRemoved", .integer).notNull().defaults(to: 0)
            }
        }
        migrator.registerMigration("v2-cleanup-columns") { database in
            try database.alter(table: TranscriptRecord.databaseTableName) { table in
                table.add(column: "cleanupMs", .integer).notNull().defaults(to: 0)
                table.add(column: "cleanupTimedOut", .boolean).notNull().defaults(to: false)
            }
        }
        migrator.registerMigration("v3-vocabulary") { database in
            try database.create(table: VocabularyWord.databaseTableName) { table in
                table.primaryKey("id", .blob)
                table.column("word", .text).notNull().unique().collate(.nocase)
                table.column("createdAt", .datetime).notNull()
                table.column("source", .text).notNull()
            }
            try database.create(table: VocabularySuggestion.databaseTableName) { table in
                table.primaryKey("word", .text).collate(.nocase)
                table.column("createdAt", .datetime).notNull()
            }
        }
        migrator.registerMigration("v4-vocabulary-aliases") { database in
            try database.alter(table: VocabularyWord.databaseTableName) { table in
                table.add(column: "aliases", .text).notNull().defaults(to: "[]")
            }
            try database.alter(table: VocabularySuggestion.databaseTableName) { table in
                table.add(column: "aliases", .text).notNull().defaults(to: "[]")
            }
        }
        migrator.registerMigration("v5-vocabulary-replaces") { database in
            try database.alter(table: VocabularyWord.databaseTableName) { table in
                table.add(column: "replaces", .text).notNull().defaults(to: "[]")
            }
        }
        migrator.registerMigration("v6-extension-entries") { database in
            try database.alter(table: TranscriptRecord.databaseTableName) { table in
                table.add(column: "source", .text)
                table.add(column: "file", .text)
            }
        }
        return migrator
    }

    func insert(_ record: TranscriptRecord) throws {
        try queue.write { try record.insert($0) }
    }

    func insert(_ record: TranscriptRecord) async throws {
        try await queue.write { try record.insert($0) }
    }

    func delete(id: UUID) throws {
        _ = try queue.write { try TranscriptRecord.deleteOne($0, key: id) }
    }

    func search(_ query: String) throws -> [TranscriptRecord] {
        try queue.read { try Self.request(matching: query).fetchAll($0) }
    }

    func observeSearch(_ query: String) -> AnyPublisher<[TranscriptRecord], Error> {
        ValueObservation
            .tracking { try Self.request(matching: query).fetchAll($0) }
            .publisher(in: queue)
            .eraseToAnyPublisher()
    }

    func stats(now: Date = Date(), calendar: Calendar = .current) throws -> UsageStats {
        try queue.read { try Self.stats(in: $0, now: now, calendar: calendar) }
    }

    func observeStats(now: @escaping @Sendable () -> Date = Date.init, calendar: Calendar = .current) -> AnyPublisher<UsageStats, Error> {
        ValueObservation
            .tracking { try Self.stats(in: $0, now: now(), calendar: calendar) }
            .publisher(in: queue)
            .eraseToAnyPublisher()
    }

    private static func stats(in database: Database, now: Date, calendar: Calendar) throws -> UsageStats {
        var accumulator = StatsAccumulator(now: now, calendar: calendar)
        let rows = try TranscriptRecord
            .filter(Column("source") == nil)
            .select(Column("createdAt"), Column("wordCount"), Column("audioSeconds"), Column("fillerWordsRemoved"), Column("appBundleID"), Column("appName"))
            .asRequest(of: StatsRow.self)
            .fetchCursor(database)
        while let row = try rows.next() { accumulator.add(row) }
        return accumulator.finish()
    }

    private static func request(matching query: String) -> QueryInterfaceRequest<TranscriptRecord> {
        let newest = TranscriptRecord.order(Column("createdAt").desc)
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return newest.limit(menuLimit) }
        return newest.filter(containsIgnoringCase(Column("finalText"), trimmed)).limit(searchLimit)
    }
}

struct TranscriptRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable, Sendable {
    static let databaseTableName = "transcript"

    var id: UUID
    var createdAt: Date
    var rawText: String
    var finalText: String
    var audioSeconds: Double
    var wordCount: Int
    var sttMs: Int
    var totalMs: Int
    var model: String
    var appBundleID: String?
    var appName: String?
    var fillerWordsRemoved: Int
    var cleanupMs: Int
    var cleanupTimedOut: Bool
    var source: String?
    var file: String?

    init(
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
        cleanupTimedOut: Bool = false,
        source: String? = nil,
        file: String? = nil
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
        self.source = source
        self.file = file
    }

    init(_ entry: ExtensionHistoryEntry) {
        self.init(rawText: entry.text, audioSeconds: entry.seconds, sttMs: 0, totalMs: 0, model: entry.extension,
                  appBundleID: nil, appName: nil, source: entry.extension, file: entry.file)
    }
}
