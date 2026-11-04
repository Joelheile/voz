import Foundation
import GRDB

/// One conversation in one app, such as a chat with Anna in Slack
struct ThreadRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable, Sendable {
    static let databaseTableName = "thread"

    var id: UUID
    var app: String
    var title: String
    var createdAt: Date
    var seenAt: Date

    private static let separators = [" - ", " — ", " – ", " | "]

    /// Window titles add unread counts and the app name, which change while the conversation stays the same
    static func title(fromWindow window: String, appName: String?) -> String? {
        var title = window.trimmingCharacters(in: .whitespacesAndNewlines)
        if let badge = title.range(of: #"^(\(\d+\+?\)|[●•*])\s*"#, options: .regularExpression) { title.removeSubrange(badge) }
        if let appName, !appName.isEmpty {
            for separator in separators where title.lowercased().hasSuffix((separator + appName).lowercased()) {
                title = String(title.dropLast(separator.count + appName.count))
            }
        }
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let namesOnlyTheApp = appName.map { title.caseInsensitiveCompare($0) == .orderedSame } ?? false
        return title.isEmpty || namesOnlyTheApp ? nil : title
    }
}

/// What happened to a draft after it was inserted
enum DraftOutcome: String, Codable, Sendable {
    /// Still being watched, or the field could not be read
    case unknown
    case kept
    case edited
    /// The field emptied while the draft was in it, as when a chat sends a message
    case sent
    case removed
}

/// Text an extension put into a field, and what you did with it
struct DraftRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable, Sendable {
    static let databaseTableName = "draft"

    var id: UUID
    var createdAt: Date
    var source: String
    var threadID: UUID?
    var transcriptID: UUID?
    var instruction: String?
    var input: String
    var output: String
    var result: String?
    var outcome: DraftOutcome

    init(id: UUID = UUID(), createdAt: Date = Date(), source: String, threadID: UUID? = nil, transcriptID: UUID? = nil,
         instruction: String? = nil, input: String = "", output: String, result: String? = nil, outcome: DraftOutcome = .unknown) {
        self.id = id
        self.createdAt = createdAt
        self.source = source
        self.threadID = threadID
        self.transcriptID = transcriptID
        self.instruction = instruction
        self.input = input
        self.output = output
        self.result = result
        self.outcome = outcome
    }
}

/// One thing you wrote, as extensions read it: a dictation or a draft
struct WrittenText: Encodable, Equatable, Sendable {
    enum Kind: String, Encodable, Sendable {
        case dictation
        case draft
    }

    let kind: Kind
    /// What ended up in the field: your edit of a draft when you changed it
    let text: String
    /// Milliseconds since 1970, like `Date.now()`
    let at: Double
    let thread: UUID?
    let source: String?
    let instruction: String?
    /// The text a draft replaced, empty for a new reply
    let input: String?
    let output: String?
    let outcome: DraftOutcome?
    /// The bundle ID and title of the conversation it was written in, so extensions can learn how you write per app and person
    var app: String? = nil
    var threadTitle: String? = nil
}

final class DraftStore: Sendable {
    static let maxLimit = 100

    private let queue: DatabaseQueue

    init(queue: DatabaseQueue) {
        self.queue = queue
    }

    func thread(app: String, title: String, at now: Date = Date()) throws -> ThreadRecord {
        try queue.write { database in
            if var thread = try ThreadRecord.filter(Column("app") == app && Column("title") == title).fetchOne(database) {
                thread.seenAt = now
                try thread.update(database)
                return thread
            }
            let thread = ThreadRecord(id: UUID(), app: app, title: title, createdAt: now, seenAt: now)
            try thread.insert(database)
            return thread
        }
    }

    /// The thread a window shows, or nil when its title names no conversation
    func thread(app: String?, window: String?, appName: String?) throws -> ThreadRecord? {
        guard let app, let window, let title = ThreadRecord.title(fromWindow: window, appName: appName) else { return nil }
        return try thread(app: app, title: title)
    }

    /// The recent dictation a draft rewrote, when it replaced exactly that text
    func transcriptID(replacedBy input: String, since: Date) throws -> UUID? {
        let input = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }
        return try queue.read { database in
            try TranscriptRecord
                .filter(Column("source") == nil && Column("createdAt") >= since)
                .filter(sql: "trim(finalText) = ?", arguments: [input])
                .order(Column("createdAt").desc)
                .fetchOne(database)?.id
        }
    }

    func insert(_ draft: DraftRecord) throws {
        try queue.write { try draft.insert($0) }
    }

    func finish(_ id: UUID, result: String?, outcome: DraftOutcome) throws {
        try queue.write { database in
            guard var draft = try DraftRecord.fetchOne(database, key: id) else { return }
            draft.result = result
            draft.outcome = outcome
            try draft.update(database)
        }
    }

    /// Newest first, each with the conversation it went into. `sources` lists the names an extension may go by.
    func recent(sources: [String]? = nil, limit: Int) throws -> [(draft: DraftRecord, thread: ThreadRecord?)] {
        try queue.read { database in
            var request = DraftRecord.order(Column("createdAt").desc)
            if let sources { request = request.filter(sources.contains(Column("source"))) }
            let drafts = try request.limit(max(0, limit)).fetchAll(database)
            let threads = try ThreadRecord.fetchAll(database, keys: Set(drafts.compactMap(\.threadID)))
            let byID = Dictionary(uniqueKeysWithValues: threads.map { ($0.id, $0) })
            return drafts.map { ($0, $0.threadID.flatMap { byID[$0] }) }
        }
    }

    /// Newest first. With a source, only that extension's drafts; without one, your dictations too.
    func written(thread: UUID? = nil, source: String? = nil, limit: Int) throws -> [WrittenText] {
        let limit = max(0, min(limit, Self.maxLimit))
        return try queue.read { database in
            var drafts = DraftRecord.order(Column("createdAt").desc)
            if let thread { drafts = drafts.filter(Column("threadID") == thread) }
            if let source { drafts = drafts.filter(Column("source") == source) }
            var written = try drafts.limit(limit).fetchAll(database).map { draft in
                WrittenText(kind: .draft, text: draft.result ?? draft.output, at: draft.createdAt.millisecondsSince1970, thread: draft.threadID,
                            source: draft.source, instruction: draft.instruction, input: draft.input, output: draft.output, outcome: draft.outcome)
            }
            if source == nil {
                var dictations = TranscriptRecord.filter(Column("source") == nil).order(Column("createdAt").desc)
                if let thread { dictations = dictations.filter(Column("threadID") == thread) }
                written += try dictations.limit(limit).fetchAll(database).map { record in
                    WrittenText(kind: .dictation, text: record.finalText, at: record.createdAt.millisecondsSince1970, thread: record.threadID,
                                source: nil, instruction: nil, input: nil, output: nil, outcome: nil)
                }
            }
            written = Array(written.sorted { $0.at > $1.at }.prefix(limit))
            let ids = Set(written.compactMap(\.thread))
            let threads = try ThreadRecord.filter(ids.contains(Column("id"))).fetchAll(database)
            let byID = Dictionary(uniqueKeysWithValues: threads.map { ($0.id, $0) })
            return written.map { entry in
                var entry = entry
                entry.app = entry.thread.flatMap { byID[$0]?.app }
                entry.threadTitle = entry.thread.flatMap { byID[$0]?.title }
                return entry
            }
        }
    }
}

private extension Date {
    var millisecondsSince1970: Double { (timeIntervalSince1970 * 1000).rounded() }
}
