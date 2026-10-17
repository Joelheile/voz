import Foundation

public struct VoiceCommandMatch: Equatable, Sendable {
    public let phrase: String
    public let leadingText: String
}

public enum VoiceCommands {
    public static func match(_ text: String, phrases: [String]) -> VoiceCommandMatch? {
        let words = wordRanges(in: text)
        let candidates = phrases
            .map { (phrase: $0, words: WordTokens.alphanumeric($0)) }
            .filter { !$0.words.isEmpty && $0.words.count <= words.count }
            .sorted { $0.words.count > $1.words.count }
        for candidate in candidates {
            let tail = words.suffix(candidate.words.count)
            guard tail.map({ text[$0].lowercased() }) == candidate.words, let first = tail.first else { continue }
            let leading = text[..<first.lowerBound].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;:")))
            return VoiceCommandMatch(phrase: candidate.phrase, leadingText: leading)
        }
        return nil
    }

    private static func wordRanges(in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var start: String.Index?
        for index in text.indices {
            let isWordCharacter = text[index].isLetter || text[index].isNumber
            if isWordCharacter, start == nil { start = index }
            if !isWordCharacter, let wordStart = start {
                ranges.append(wordStart..<index)
                start = nil
            }
        }
        if let start { ranges.append(start..<text.endIndex) }
        return ranges
    }
}
