import Combine
import FluidAudio
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
    var aliases: [String]
    var replaces: [String]

    init(id: UUID = UUID(), word: String, createdAt: Date = Date(), source: VocabularySource, aliases: [String] = [], replaces: [String] = []) {
        self.id = id
        self.word = word
        self.createdAt = createdAt
        self.source = source
        self.aliases = aliases
        self.replaces = replaces
    }
}

struct VocabularySuggestion: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable, Sendable {
    static let databaseTableName = "vocabulary_suggestion"

    var word: String
    var createdAt: Date
    var aliases: [String]
    var id: String { word }

    init(word: String, createdAt: Date = Date(), aliases: [String] = []) {
        self.word = word
        self.createdAt = createdAt
        self.aliases = aliases
    }
}

struct VocabularyTerm: Equatable, Sendable {
    let word: String
    let aliases: [String]
}

struct VocabularyRule: Equatable, Sendable {
    let heard: String
    let word: String

    static func apply(_ rules: [VocabularyRule], to text: String) -> String {
        rules.reduce(text) { VocabularyCasing.replaceWholeWord($1.heard, with: $1.word, in: $0) }
    }

    static func parse(_ entry: String) -> (heard: String?, word: String) {
        let parts = entry.components(separatedBy: "->").flatMap { $0.components(separatedBy: "→") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let heard = parts.count == 2 && !parts[0].isEmpty ? parts[0] : nil
        return (heard, parts.last ?? "")
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

    func terms() throws -> [VocabularyTerm] {
        try queue.read { database in
            try VocabularyWord.order(Column("word").collating(.nocase)).fetchAll(database).map {
                VocabularyTerm(word: $0.word, aliases: $0.aliases)
            }
        }
    }

    func rules() throws -> [VocabularyRule] {
        try queue.read { database in
            try VocabularyWord.order(Column("word").collating(.nocase)).fetchAll(database).flatMap { word in
                word.replaces.map { VocabularyRule(heard: $0, word: word.word) }
            }
        }
    }

    // A failed read costs one transcript its vocabulary, which beats failing the transcript
    func rulesOrLogged() -> [VocabularyRule] {
        do {
            return try rules()
        } catch {
            Log.app.error("Vocabulary rules read failed: \(error.localizedDescription, privacy: .private)")
            return []
        }
    }

    func wordsOrLogged() -> [String] {
        do {
            return try words()
        } catch {
            Log.app.error("Vocabulary read failed: \(error.localizedDescription, privacy: .private)")
            return []
        }
    }

    func add(_ entry: String, source: VocabularySource, aliases: [String] = []) throws {
        let (heard, word) = VocabularyRule.parse(entry)
        guard !word.isEmpty else { return }
        try queue.write { database in
            let exists = try VocabularyWord.filter(Column("word") == word).fetchCount(database) > 0
            if !exists { try VocabularyWord(word: word, source: source, aliases: aliases).insert(database) }
            _ = try VocabularySuggestion.deleteOne(database, key: word)
        }
        if let heard { try addRule(VocabularyRule(heard: heard, word: word)) }
    }

    func addRule(_ rule: VocabularyRule) throws {
        guard rule.heard.caseInsensitiveCompare(rule.word) != .orderedSame else { return }
        try update(rule.word) { word in
            if !word.replaces.contains(where: { $0.caseInsensitiveCompare(rule.heard) == .orderedSame }) { word.replaces.append(rule.heard) }
            if !word.aliases.contains(where: { $0.caseInsensitiveCompare(rule.heard) == .orderedSame }) { word.aliases.append(rule.heard) }
        }
    }

    func removeRule(_ rule: VocabularyRule) throws {
        try update(rule.word) { word in
            word.replaces.removeAll { $0.caseInsensitiveCompare(rule.heard) == .orderedSame }
            word.aliases.removeAll { $0.caseInsensitiveCompare(rule.heard) == .orderedSame }
        }
    }

    func contains(_ word: String) throws -> Bool {
        try queue.read { try VocabularyWord.filter(Column("word") == word).fetchCount($0) > 0 }
    }

    func remove(id: UUID) throws {
        _ = try queue.write { try VocabularyWord.deleteOne($0, key: id) }
    }

    private func update(_ word: String, _ change: (inout VocabularyWord) -> Void) throws {
        try queue.write { database in
            guard var record = try VocabularyWord.filter(Column("word") == word).fetchOne(database) else { return }
            change(&record)
            try record.update(database)
        }
    }

    func knows(_ word: String) throws -> Bool {
        try queue.read { database in
            try VocabularyWord.filter(Column("word") == word).fetchCount(database) > 0
                || VocabularySuggestion.filter(Column("word") == word).fetchCount(database) > 0
        }
    }

    func suggest(_ word: String, aliases: [String] = []) throws {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try queue.write { database in
            let known = try VocabularyWord.filter(Column("word") == trimmed).fetchCount(database) > 0
            let pending = try VocabularySuggestion.filter(Column("word") == trimmed).fetchCount(database) > 0
            guard !known, !pending else { return }
            try VocabularySuggestion(word: trimmed, aliases: aliases).insert(database)
        }
    }

    func accept(_ suggestion: VocabularySuggestion) throws {
        try add(suggestion.word, source: .learned, aliases: suggestion.aliases)
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
        vocabulary.reduce(text) { replaceWholeWord($1, with: $1, in: $0) }
    }

    static func replaceWholeWord(_ find: String, with replacement: String, in text: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: find)
        let pattern = "(?<![\\p{L}\\p{N}])\(escaped)(?![\\p{L}\\p{N}])"
        return text.replacingOccurrences(
            of: pattern,
            with: NSRegularExpression.escapedTemplate(for: replacement),
            options: [.regularExpression, .caseInsensitive]
        )
    }
}

struct VocabularyCandidate: Equatable {
    let word: String
    let heardAs: String
}

enum EditLearner {
    static let maxWords = 400
    static let minimumSimilarity = 0.5

    static func suggestions(
        inserted: String,
        current: String,
        isKnownWord: (String) -> Bool
    ) -> [VocabularyCandidate] {
        edits(inserted: inserted, current: current)
            .filter { isWorthLearning($0, isKnownWord: isKnownWord) }
            .reduce(into: [VocabularyCandidate]()) { unique, candidate in
                if !unique.contains(where: { $0.word == candidate.word }) { unique.append(candidate) }
            }
    }

    static func edits(inserted: String, current: String) -> [VocabularyCandidate] {
        let before = WordTokens.split(inserted)
        let after = WordTokens.split(current)
        guard !before.isEmpty, before.count <= maxWords, after.count <= maxWords * 4 else { return [] }
        return replacements(from: before, to: after).map { VocabularyCandidate(word: $0.replacement, heardAs: $0.original) }
    }

    static func isWorthLearning(_ candidate: VocabularyCandidate, isKnownWord: (String) -> Bool) -> Bool {
        candidate.word != candidate.heardAs && looksMisheard(candidate) && looksLikeTermWorthLearning(candidate.word, isKnownWord: isKnownWord)
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

    private static func looksMisheard(_ candidate: VocabularyCandidate) -> Bool {
        let original = candidate.heardAs.lowercased()
        let corrected = candidate.word.lowercased()
        let distance = StringUtils.levenshteinDistance(original, corrected)
        return 1 - Double(distance) / Double(max(original.count, corrected.count)) >= minimumSimilarity
    }

    private static func looksLikeTermWorthLearning(_ word: String, isKnownWord: (String) -> Bool) -> Bool {
        guard word.count >= 2, word.contains(where: \.isLetter) else { return false }
        let hasDigit = word.contains(where: \.isNumber)
        let isCamelCase = zip(word, word.dropFirst()).contains { $0.isLowercase && $1.isUppercase }
        return hasDigit || isCamelCase || !isKnownWord(word)
    }
}
