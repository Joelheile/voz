import Foundation
import NaturalLanguage

enum WordTokens {
    static func split(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map { stripEdges(String($0)) }.filter { !$0.isEmpty }
    }

    static func normalized(_ text: String) -> [String] {
        split(text).map { $0.lowercased() }
    }

    static func alphanumeric(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }

    static func stripEdges(_ word: String) -> String {
        word.trimmingCharacters(in: .punctuationCharacters.union(.symbols))
    }
}

enum NumberWords {
    private static let words: Set<String> = [
        "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
        "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen",
        "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety", "hundred", "thousand",
        "first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth",
        "null", "eins", "zwei", "drei", "vier", "fünf", "sechs", "sieben", "acht", "neun", "zehn",
        "elf", "zwölf", "dreizehn", "vierzehn", "fünfzehn", "sechzehn", "siebzehn", "achtzehn", "neunzehn",
        "zwanzig", "dreißig", "vierzig", "fünfzig", "sechzig", "siebzig", "achtzig", "neunzig", "hundert", "tausend",
        "erstens", "zweitens", "drittens", "viertens", "fünftens",
        "ersten", "zweiten", "dritten", "vierten", "fünften", "sechsten", "siebten", "achten", "neunten", "zehnten",
        "fünfzehnten", "zwanzigsten", "dreißigsten",
    ]

    static func isNumber(_ word: String) -> Bool {
        let lowered = word.lowercased()
        return words.contains(lowered) || lowered.contains(where: \.isNumber)
    }
}

struct RulePassResult: Equatable, Sendable {
    let text: String
    let removed: Int
}

enum FillerWords {
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

    private static let englishUmPattern = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}])um(?![\p{L}\p{N}])[,.…]*\s*"#,
        options: [.caseInsensitive]
    )

    static func removeObvious(from text: String) -> RulePassResult {
        var result = text
        var removed = 0
        let patterns = isEnglish(text) ? [unambiguousPattern, englishUmPattern] : [unambiguousPattern, punctuatedUmPattern]
        for pattern in patterns {
            let range = NSRange(result.startIndex..., in: result)
            removed += pattern.numberOfMatches(in: result, range: range)
            result = pattern.stringByReplacingMatches(in: result, range: range, withTemplate: "")
        }
        guard removed > 0 else { return RulePassResult(text: text, removed: 0) }
        return RulePassResult(text: capitalizingStart(tidy(result)), removed: removed)
    }

    private static func isEnglish(_ text: String) -> Bool {
        guard WordTokens.normalized(text).contains("um") else { return false }
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.english, .german]
        recognizer.processString(text)
        return (recognizer.languageHypotheses(withMaximum: 1)[.english] ?? 0) >= 0.9
    }

    static func estimateRemoved(before: String, after: String) -> Int {
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
