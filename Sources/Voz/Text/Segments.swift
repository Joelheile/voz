import Foundation

enum SegmentJoiner {
    private static let sentenceEnders = CharacterSet(charactersIn: ".!?…:\n")
    private static let closers = CharacterSet(charactersIn: "\"\u{201D}\u{00BB}')]")

    static func join(_ texts: [String]) -> String {
        texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func join(cleaned: [String?], fallback: [String]) -> String {
        var chosen = fallback.indices.map { index in
            index < cleaned.count ? (cleaned[index] ?? fallback[index]) : fallback[index]
        }
        for index in chosen.indices.dropLast() where !endsSentence(fallback[index]) {
            chosen[index] = droppingFinalPeriod(chosen[index])
        }
        return join(chosen)
    }

    private static func droppingFinalPeriod(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix("."), !trimmed.hasSuffix("..") else { return text }
        return String(trimmed.dropLast())
    }

    private static func endsSentence(_ text: String) -> Bool {
        let core = text.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: closers)
        guard let last = core.unicodeScalars.last else { return true }
        return sentenceEnders.contains(last)
    }
}

enum SentenceChunks {
    static let targetWords = 70
    static let minimumTailWords = 8

    private static let wordPattern = try! NSRegularExpression(pattern: #"\S+\s*"#)
    private static let closingQuotes = CharacterSet(charactersIn: "\"\u{201D}\u{00BB}')")

    static func split(_ text: String, targetWords: Int = SentenceChunks.targetWords) -> [String] {
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

    static func splitLastSentence(_ text: String) -> (before: String, last: String) {
        let sentences = sentences(in: text)
        return (sentences.dropLast().joined().joined(), sentences.last?.joined() ?? "")
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

struct TextEdit: Equatable, Sendable {
    let utf8Range: Range<Int>
    let replacement: String
}

enum TextSplice {
    static func apply(_ edits: [TextEdit], to text: String) -> String {
        var bytes = Array(text.utf8)
        var lowerLimit = bytes.count
        for edit in edits.sorted(by: { $0.utf8Range.lowerBound > $1.utf8Range.lowerBound }) {
            guard edit.utf8Range.upperBound <= lowerLimit, edit.utf8Range.upperBound <= bytes.count else { continue }
            bytes.replaceSubrange(edit.utf8Range, with: Array(edit.replacement.utf8))
            lowerLimit = edit.utf8Range.lowerBound
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
