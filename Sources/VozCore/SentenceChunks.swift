import Foundation

public enum SentenceChunks {
    public static let targetWords = 70
    public static let minimumTailWords = 8

    private static let wordPattern = try! NSRegularExpression(pattern: #"\S+\s*"#)
    private static let closingQuotes = CharacterSet(charactersIn: "\"\u{201D}\u{00BB}')")

    public static func split(_ text: String, targetWords: Int = SentenceChunks.targetWords) -> [String] {
        var chunks: [[String]] = []
        for sentence in sentences(in: text).flatMap({ splitLong($0, limit: targetWords) }) {
            if let last = chunks.last, last.count + sentence.count <= targetWords {
                chunks[chunks.count - 1] += sentence
            } else {
                chunks.append(sentence)
            }
        }
        if chunks.count > 1, let tail = chunks.last, tail.count < minimumTailWords {
            chunks.removeLast()
            chunks[chunks.count - 1] += tail
        }
        return chunks.map { $0.joined() }
    }

    private static func sentences(in text: String) -> [[String]] {
        var sentences: [[String]] = []
        var current: [String] = []
        for match in wordPattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            let word = String(text[Range(match.range, in: text)!])
            current.append(word)
            if endsSentence(word) {
                sentences.append(current)
                current = []
            }
        }
        if !current.isEmpty { sentences.append(current) }
        return sentences
    }

    private static func endsSentence(_ word: String) -> Bool {
        if word.contains("\n") { return true }
        let core = word.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: closingQuotes)
        guard let last = core.last else { return false }
        return ".!?".contains(last)
    }

    private static func splitLong(_ sentence: [String], limit: Int) -> [[String]] {
        guard sentence.count > limit else { return [sentence] }
        return stride(from: 0, to: sentence.count, by: limit).map { Array(sentence[$0..<min($0 + limit, sentence.count)]) }
    }
}
