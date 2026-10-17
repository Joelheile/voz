import Combine
import Foundation
import GRDB

public final class HistoryStore: Sendable {
    public static let menuLimit = 10

    private static let containsIgnoringCase = DatabaseFunction("contains_ignoring_case", argumentCount: 2, pure: true) { values in
        guard let haystack = String.fromDatabaseValue(values[0]), let needle = String.fromDatabaseValue(values[1]) else {
            return nil
        }
        return haystack.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private let queue: DatabaseQueue
    public let vocabulary: VocabularyStore

    public init(path: String? = nil) throws {
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
        return migrator
    }

    public func insert(_ record: TranscriptRecord) throws {
        try queue.write { try record.insert($0) }
    }

    public func delete(id: UUID) throws {
        _ = try queue.write { try TranscriptRecord.deleteOne($0, key: id) }
    }

    public func recent(limit: Int = HistoryStore.menuLimit) throws -> [TranscriptRecord] {
        try queue.read { try Self.request(matching: "", limit: limit).fetchAll($0) }
    }

    public func search(_ query: String, limit: Int? = nil) throws -> [TranscriptRecord] {
        try queue.read { try Self.request(matching: query, limit: limit).fetchAll($0) }
    }

    public func observeSearch(_ query: String) -> AnyPublisher<[TranscriptRecord], Error> {
        ValueObservation
            .tracking { try Self.request(matching: query, limit: nil).fetchAll($0) }
            .publisher(in: queue)
            .eraseToAnyPublisher()
    }

    public func stats(now: Date = Date(), calendar: Calendar = .current) throws -> UsageStats {
        try queue.read { try Self.stats(in: $0, now: now, calendar: calendar) }
    }

    public func observeStats(calendar: Calendar = .current) -> AnyPublisher<UsageStats, Error> {
        ValueObservation
            .tracking { try Self.stats(in: $0, now: Date(), calendar: calendar) }
            .publisher(in: queue)
            .eraseToAnyPublisher()
    }

    private static func stats(in database: Database, now: Date, calendar: Calendar) throws -> UsageStats {
        var accumulator = StatsAccumulator(now: now, calendar: calendar)
        let rows = try TranscriptRecord
            .select(Column("createdAt"), Column("wordCount"), Column("audioSeconds"), Column("appName"), Column("fillerWordsRemoved"))
            .asRequest(of: StatsRow.self)
            .fetchCursor(database)
        while let row = try rows.next() { accumulator.add(row) }
        return accumulator.finish()
    }

    private static func request(matching query: String, limit: Int?) -> QueryInterfaceRequest<TranscriptRecord> {
        var request = TranscriptRecord.order(Column("createdAt").desc)
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            request = request.filter(containsIgnoringCase(Column("finalText"), trimmed))
        }
        if let limit { request = request.limit(limit) }
        return request
    }
}
