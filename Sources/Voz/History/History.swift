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
    let drafts: DraftStore

    init(path: String? = nil) throws {
        var configuration = Configuration()
        configuration.prepareDatabase { database in
            database.add(function: Self.containsIgnoringCase)
        }
        queue = try path.map { try DatabaseQueue(path: $0, configuration: configuration) }
            ?? DatabaseQueue(configuration: configuration)
        try Self.migrator.migrate(queue)
        vocabulary = VocabularyStore(queue: queue)
        drafts = DraftStore(queue: queue)
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
        migrator.registerMigration("v7-search-index") { database in
            try database.create(virtualTable: TranscriptSearch.indexTable, using: FTS5()) { table in
                table.synchronize(withTable: TranscriptRecord.databaseTableName)
                table.tokenizer = FTS5TokenizerDescriptor(components: ["trigram", "remove_diacritics", "1"])
                table.column("finalText")
                table.column("appName")
            }
        }
        migrator.registerMigration("v7-threads-drafts") { database in
            try database.create(table: ThreadRecord.databaseTableName) { table in
                table.primaryKey("id", .blob)
                table.column("app", .text).notNull()
                table.column("title", .text).notNull()
                table.column("createdAt", .datetime).notNull()
                table.column("seenAt", .datetime).notNull()
                table.uniqueKey(["app", "title"])
            }
            try database.alter(table: TranscriptRecord.databaseTableName) { table in
                table.add(column: "threadID", .blob).references(ThreadRecord.databaseTableName, onDelete: .setNull)
            }
            try database.create(index: "transcript_on_threadID", on: TranscriptRecord.databaseTableName, columns: ["threadID", "createdAt"])
            try database.create(table: DraftRecord.databaseTableName) { table in
                table.primaryKey("id", .blob)
                table.column("createdAt", .datetime).notNull()
                table.column("source", .text).notNull()
                table.column("threadID", .blob).references(ThreadRecord.databaseTableName, onDelete: .setNull)
                table.column("transcriptID", .blob).references(TranscriptRecord.databaseTableName, onDelete: .setNull)
                table.column("instruction", .text)
                table.column("input", .text).notNull()
                table.column("output", .text).notNull()
                table.column("result", .text)
                table.column("outcome", .text).notNull()
            }
            try database.create(index: "draft_on_threadID", on: DraftRecord.databaseTableName, columns: ["threadID", "createdAt"])
            try database.create(index: "draft_on_source", on: DraftRecord.databaseTableName, columns: ["source", "createdAt"])
        }
        migrator.registerMigration("v7-history-copies") { database in
            try database.alter(table: TranscriptRecord.databaseTableName) { table in
                table.add(column: "copies", .text)
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
        try queue.read { try Self.records(matching: query, in: $0) }
    }

    func recent(matching query: String = "", app: String? = nil, since: Date? = nil, limit: Int) throws -> [TranscriptRecord] {
        var request = TranscriptRecord.all()
        if let app { request = request.filter(Self.containsIgnoringCase(Column("appName"), app)) }
        if let since { request = request.filter(Column("createdAt") >= since) }
        return try queue.read { try Self.records(matching: TranscriptSearch(query), in: request, limit: limit, database: $0) }
    }

    func observeSearch(_ query: String) -> AnyPublisher<[TranscriptRecord], Error> {
        ValueObservation
            .tracking { try Self.records(matching: query, in: $0) }
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

    private static func records(matching query: String, in database: Database) throws -> [TranscriptRecord] {
        let search = TranscriptSearch(query)
        return try records(matching: search, in: TranscriptRecord.all(), limit: search.isEmpty ? menuLimit : searchLimit, database: database)
    }

    private static func records(
        matching search: TranscriptSearch,
        in base: QueryInterfaceRequest<TranscriptRecord>,
        limit: Int,
        database: Database
    ) throws -> [TranscriptRecord] {
        var request = base
        if let days = search.days {
            request = request.filter(Column("createdAt") >= days.start && Column("createdAt") < days.end)
        }
        for term in search.shortTerms {
            request = request.filter(containsIgnoringCase(Column("finalText"), term) || containsIgnoringCase(Column("appName"), term))
        }
        let exact = try request
            .filter(indexed(search.allTermsPattern))
            .order(Column("createdAt").desc)
            .limit(limit)
            .fetchAll(database)
        guard exact.isEmpty, let anyTrigram = search.anyTrigramPattern else { return exact }
        return try request
            .filter(indexed(anyTrigram, best: TranscriptSearch.fuzzyCandidates))
            .fetchAll(database)
            .map { (record: $0, share: search.fuzzyShare(of: $0)) }
            .filter { $0.share >= TranscriptSearch.fuzzyMinimumShare }
            .sorted { ($0.share, $0.record.createdAt) > ($1.share, $1.record.createdAt) }
            .prefix(limit)
            .map(\.record)
    }

    private static func indexed(_ pattern: String?) -> SQLExpression {
        guard let pattern else { return true.sqlExpression }
        return SQL("rowid IN (SELECT rowid FROM \(sql: TranscriptSearch.indexTable) WHERE \(sql: TranscriptSearch.indexTable) MATCH \(pattern))").sqlExpression
    }

    private static func indexed(_ pattern: String, best limit: Int) -> SQLExpression {
        SQL("rowid IN (SELECT rowid FROM \(sql: TranscriptSearch.indexTable) WHERE \(sql: TranscriptSearch.indexTable) MATCH \(pattern) ORDER BY rank LIMIT \(limit))").sqlExpression
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
    var threadID: UUID?
    var copies: [HistoryCopy]?

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
        file: String? = nil,
        threadID: UUID? = nil,
        copies: [HistoryCopy]? = nil
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
        self.threadID = threadID
        self.copies = copies
    }

    init(_ entry: ExtensionHistoryEntry) {
        self.init(rawText: entry.text, audioSeconds: entry.seconds, sttMs: 0, totalMs: 0, model: entry.extension,
                  appBundleID: nil, appName: nil, source: entry.extension, file: entry.file, copies: entry.copies)
    }
}
