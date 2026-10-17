import Combine
import Foundation
import GRDB

public enum VocabularySource: String, Codable, Sendable {
    case manual
    case learned
}

public struct VocabularyWord: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable, Sendable {
    public static let databaseTableName = "vocabulary"

    public var id: UUID
    public var word: String
    public var createdAt: Date
    public var source: VocabularySource

    public init(id: UUID = UUID(), word: String, createdAt: Date = Date(), source: VocabularySource) {
        self.id = id
        self.word = word
        self.createdAt = createdAt
        self.source = source
    }
}

public struct VocabularySuggestion: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable, Sendable {
    public static let databaseTableName = "vocabulary_suggestion"

    public var word: String
    public var createdAt: Date
    public var id: String { word }

    public init(word: String, createdAt: Date = Date()) {
        self.word = word
        self.createdAt = createdAt
    }
}

public struct VocabularySnapshot: Equatable, Sendable {
    public let words: [VocabularyWord]
    public let suggestions: [VocabularySuggestion]

    public init(words: [VocabularyWord], suggestions: [VocabularySuggestion]) {
        self.words = words
        self.suggestions = suggestions
    }
}

public final class VocabularyStore: Sendable {
    private let queue: DatabaseQueue

    init(queue: DatabaseQueue) {
        self.queue = queue
    }

    public func words() throws -> [String] {
        try queue.read { database in
            try VocabularyWord.order(Column("word").collating(.nocase)).fetchAll(database).map(\.word)
        }
    }

    public func add(_ word: String, source: VocabularySource) throws {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try queue.write { database in
            let exists = try VocabularyWord.filter(Column("word") == trimmed).fetchCount(database) > 0
            guard !exists else { return }
            try VocabularyWord(word: trimmed, source: source).insert(database)
            _ = try VocabularySuggestion.deleteOne(database, key: trimmed)
        }
    }

    public func remove(id: UUID) throws {
        _ = try queue.write { try VocabularyWord.deleteOne($0, key: id) }
    }

    public func suggest(_ word: String) throws {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try queue.write { database in
            let known = try VocabularyWord.filter(Column("word") == trimmed).fetchCount(database) > 0
            let pending = try VocabularySuggestion.filter(Column("word") == trimmed).fetchCount(database) > 0
            guard !known, !pending else { return }
            try VocabularySuggestion(word: trimmed).insert(database)
        }
    }

    public func accept(_ suggestion: VocabularySuggestion) throws {
        try add(suggestion.word, source: .learned)
        try dismiss(suggestion)
    }

    public func dismiss(_ suggestion: VocabularySuggestion) throws {
        _ = try queue.write { try VocabularySuggestion.deleteOne($0, key: suggestion.word) }
    }

    public func snapshot() throws -> VocabularySnapshot {
        try queue.read(Self.fetchSnapshot)
    }

    public func observe() -> AnyPublisher<VocabularySnapshot, Error> {
        ValueObservation
            .tracking(Self.fetchSnapshot)
            .publisher(in: queue)
            .eraseToAnyPublisher()
    }

    private static func fetchSnapshot(_ database: Database) throws -> VocabularySnapshot {
        VocabularySnapshot(
            words: try VocabularyWord.order(Column("createdAt").desc).fetchAll(database),
            suggestions: try VocabularySuggestion.order(Column("createdAt").desc).fetchAll(database)
        )
    }
}
