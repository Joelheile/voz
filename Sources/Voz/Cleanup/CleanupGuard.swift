import Foundation

enum CleanupRejection: String, Sendable, Equatable {
    case empty
    case refusal
    case leakedTags
    case tooLong
    case changedWords
}

enum CleanupGuard {
    static let maxLengthRatio = 1.3

    private static let refusalPrefixes: [[String]] = [
        ["i'm", "sorry"], ["i", "am", "sorry"], ["i", "can't"], ["i", "cannot"], ["sure"], ["here", "is"], ["here's"],
        ["please", "provide"], ["entschuldigung"], ["ich", "kann"],
    ]
    private static let outputLabels = ["output:", "cleaned:"]

    static func rejection(raw: String, cleaned: String, mode: CleanupMode, vocabulary: [String] = []) -> CleanupRejection? {
        let rawWords = WordTokens.alphanumeric(raw)
        let cleanedWords = WordTokens.alphanumeric(cleaned)
        guard !cleanedWords.isEmpty, !rawWords.isEmpty else { return .empty }
        if isRefusal(raw: raw, cleaned: cleaned) { return .refusal }
        if hasLeakedMarkup(raw: raw, cleaned: cleaned) { return .leakedTags }
        guard Double(cleanedWords.count) <= Double(rawWords.count) * maxLengthRatio else { return .tooLong }
        let preferred = Set(WordTokens.alphanumeric(vocabulary.joined(separator: " ")))
        if mode == .light, !onlyDeletes(raw: rawWords, cleaned: cleanedWords.filter { !preferred.contains($0) }) { return .changedWords }
        return nil
    }

    /// Each cleaned word appears in the raw words, in order. One cleaned word may join neighbors, as in "chat GPT" to "ChatGPT".
    static func onlyDeletes(raw: [String], cleaned: [String]) -> Bool {
        var next = raw.startIndex
        for word in cleaned {
            guard let end = end(of: word, in: raw, from: next) else { return false }
            next = end
        }
        return true
    }

    private static func end(of word: String, in raw: [String], from start: Int) -> Int? {
        for first in start..<raw.endIndex {
            var joined = ""
            for index in first..<raw.endIndex {
                joined += raw[index]
                if joined == word { return index + 1 }
                guard word.hasPrefix(joined) else { break }
            }
        }
        return nil
    }

    private static func isRefusal(raw: String, cleaned: String) -> Bool {
        let cleanedStart = leadingWords(cleaned)
        let rawStart = leadingWords(raw)
        return refusalPrefixes.contains { prefix in
            cleanedStart.starts(with: prefix) && !rawStart.starts(with: prefix)
        }
    }

    private static func leadingWords(_ text: String) -> [String] {
        WordTokens.normalized(text.replacingOccurrences(of: "\u{2019}", with: "'")).prefix(3).map { $0 }
    }

    private static func hasLeakedMarkup(raw: String, cleaned: String) -> Bool {
        if cleaned.contains("<"), !raw.contains("<") { return true }
        let lowered = cleaned.lowercased()
        let rawLowered = raw.lowercased()
        return outputLabels.contains { lowered.hasPrefix($0) && !rawLowered.hasPrefix($0) }
    }
}
