import Foundation

public enum EditLearner {
    public static let maxWords = 400

    public static func suggestions(
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
