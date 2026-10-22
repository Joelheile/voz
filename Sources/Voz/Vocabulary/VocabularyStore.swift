import Combine
import Foundation
import GRDB

enum VocabularySource: String, Codable, Sendable {
    case manual
    case learned
}

struct VocabularyWord: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable, Sendable {
    static let databaseTableName = "vocabulary"

    var id: UUID
    var word: String
    var createdAt: Date
    var source: VocabularySource

    init(id: UUID = UUID(), word: String, createdAt: Date = Date(), source: VocabularySource) {
        self.id = id
        self.word = word
        self.createdAt = createdAt
        self.source = source
    }
}

struct VocabularySuggestion: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable, Sendable {
    static let databaseTableName = "vocabulary_suggestion"

    var word: String
    var createdAt: Date
    var id: String { word }

    init(word: String, createdAt: Date = Date()) {
        self.word = word
        self.createdAt = createdAt
    }
}

struct VocabularySnapshot: Equatable, Sendable {
    let words: [VocabularyWord]
    let suggestions: [VocabularySuggestion]
}

final class VocabularyStore: Sendable {
    private let queue: DatabaseQueue

    init(queue: DatabaseQueue) {
        self.queue = queue
    }

    func words() throws -> [String] {
        try queue.read { database in
            try VocabularyWord.order(Column("word").collating(.nocase)).fetchAll(database).map(\.word)
        }
    }

    func add(_ word: String, source: VocabularySource) throws {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try queue.write { database in
            let exists = try VocabularyWord.filter(Column("word") == trimmed).fetchCount(database) > 0
            guard !exists else { return }
            try VocabularyWord(word: trimmed, source: source).insert(database)
            _ = try VocabularySuggestion.deleteOne(database, key: trimmed)
        }
    }

    func remove(id: UUID) throws {
        _ = try queue.write { try VocabularyWord.deleteOne($0, key: id) }
    }

    func suggest(_ word: String) throws {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try queue.write { database in
            let known = try VocabularyWord.filter(Column("word") == trimmed).fetchCount(database) > 0
            let pending = try VocabularySuggestion.filter(Column("word") == trimmed).fetchCount(database) > 0
            guard !known, !pending else { return }
            try VocabularySuggestion(word: trimmed).insert(database)
        }
    }

    func accept(_ suggestion: VocabularySuggestion) throws {
        try add(suggestion.word, source: .learned)
        try dismiss(suggestion)
    }

    func dismiss(_ suggestion: VocabularySuggestion) throws {
        _ = try queue.write { try VocabularySuggestion.deleteOne($0, key: suggestion.word) }
    }

    func snapshot() throws -> VocabularySnapshot {
        try queue.read(Self.fetchSnapshot)
    }

    func observe() -> AnyPublisher<VocabularySnapshot, Error> {
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

enum VocabularyCasing {
    static func apply(_ vocabulary: [String], to text: String) -> String {
        vocabulary.reduce(text) { current, word in
            let escaped = NSRegularExpression.escapedPattern(for: word)
            let pattern = "(?<![\\p{L}\\p{N}])\(escaped)(?![\\p{L}\\p{N}])"
            return current.replacingOccurrences(
                of: pattern,
                with: NSRegularExpression.escapedTemplate(for: word),
                options: [.regularExpression, .caseInsensitive]
            )
        }
    }
}

enum EditLearner {
    static let maxWords = 400

    static func suggestions(
        inserted: String,
        current: String,
        isKnownWord: (String) -> Bool
    ) -> [String] {
        let before = WordTokens.split(inserted)
        let after = WordTokens.split(current)
        guard !before.isEmpty, before.count <= maxWords, after.count <= maxWords * 4 else { return [] }
        return replacements(from: before, to: after)
            .filter { $0.original != $0.replacement }
            .filter { looksLikeTermWorthLearning($0.replacement, isKnownWord: isKnownWord) }
            .map(\.replacement)
            .reduce(into: [String]()) { unique, word in
                if !unique.contains(word) { unique.append(word) }
            }
    }

    private struct Replacement {
        let original: String
        let replacement: String
    }

    private static func replacements(from before: [String], to after: [String]) -> [Replacement] {
        let table = commonSubsequenceLengths(before, after)
        var result: [Replacement] = []
        var removed: [String] = []
        var added: [String] = []
        func flush() {
            if !removed.isEmpty, removed.count == added.count {
                result += zip(removed, added).map { Replacement(original: $0, replacement: $1) }
            }
            removed = []
            added = []
        }
        var i = 0
        var j = 0
        while i < before.count || j < after.count {
            if i < before.count, j < after.count, before[i] == after[j] {
                flush()
                i += 1
                j += 1
            } else if j < after.count, i == before.count || table[i][j + 1] >= table[i + 1][j] {
                added.append(after[j])
                j += 1
            } else {
                removed.append(before[i])
                i += 1
            }
        }
        flush()
        return result
    }

    private static func commonSubsequenceLengths(_ lhs: [String], _ rhs: [String]) -> [[Int]] {
        var table = Array(repeating: Array(repeating: 0, count: rhs.count + 1), count: lhs.count + 1)
        for i in stride(from: lhs.count - 1, through: 0, by: -1) {
            for j in stride(from: rhs.count - 1, through: 0, by: -1) {
                table[i][j] = lhs[i] == rhs[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        return table
    }

    private static func looksLikeTermWorthLearning(_ word: String, isKnownWord: (String) -> Bool) -> Bool {
        guard word.count >= 2, word.contains(where: \.isLetter) else { return false }
        let startsCapitalized = word.first?.isUppercase ?? false
        let hasDigit = word.contains(where: \.isNumber)
        let isCamelCase = zip(word, word.dropFirst()).contains { $0.isLowercase && $1.isUppercase }
        return startsCapitalized || hasDigit || isCamelCase || !isKnownWord(word)
    }
}
