import Foundation

public struct FillerPassResult: Equatable, Sendable {
    public let text: String
    public let removed: Int

    public init(text: String, removed: Int) {
        self.text = text
        self.removed = removed
    }
}

public enum FillerWords {
    private static let singleWordFillers = ["um", "uh", "uhm", "like", "halt", "sozusagen", "quasi", "also", "ähm", "äh", "öhm"]
    private static let phraseFillers = [["you", "know"], ["i", "mean"]]

    private static let unambiguousPattern = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}])(?:uh+m*|uhm+|umm+|erm+|äh+m*|öh+m*)(?![\p{L}\p{N}])[,.…]*\s*"#,
        options: [.caseInsensitive]
    )
    private static let punctuatedUmPattern = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}])um(?![\p{L}\p{N}])\s*[,.…]+\s*"#,
        options: [.caseInsensitive]
    )

    public static func removeObvious(from text: String) -> FillerPassResult {
        var result = text
        var removed = 0
        for pattern in [unambiguousPattern, punctuatedUmPattern] {
            let range = NSRange(result.startIndex..., in: result)
            removed += pattern.numberOfMatches(in: result, range: range)
            result = pattern.stringByReplacingMatches(in: result, range: range, withTemplate: "")
        }
        guard removed > 0 else { return FillerPassResult(text: text, removed: 0) }
        return FillerPassResult(text: capitalizingStart(tidy(result)), removed: removed)
    }

    public static func estimateRemoved(before: String, after: String) -> Int {
        let beforeWords = WordTokens.normalized(before)
        let afterWords = WordTokens.normalized(after)
        let single = singleWordFillers.reduce(0) { total, filler in
            total + max(0, count(of: [filler], in: beforeWords) - count(of: [filler], in: afterWords))
        }
        let phrases = phraseFillers.reduce(0) { total, phrase in
            total + max(0, count(of: phrase, in: beforeWords) - count(of: phrase, in: afterWords))
        }
        return single + phrases
    }

    private static func count(of phrase: [String], in words: [String]) -> Int {
        guard !phrase.isEmpty, words.count >= phrase.count else { return 0 }
        return (0...(words.count - phrase.count)).filter { Array(words[$0..<($0 + phrase.count)]) == phrase }.count
    }

    private static func tidy(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+([,.;:!?])"#, with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func capitalizingStart(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}
