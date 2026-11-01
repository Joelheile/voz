import Foundation

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

enum FillerWords {
    private static let singleWordFillers = ["um", "uh", "uhm", "like", "halt", "sozusagen", "quasi", "also", "ähm", "äh", "öhm"]
    private static let phraseFillers = [["you", "know"], ["i", "mean"]]

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
}
