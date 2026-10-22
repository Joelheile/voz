import Foundation

enum SpokenPunctuation {
    private enum Symbol {
        case comma
        case period
        case question
        case line
        case paragraph

        var text: String {
            switch self {
            case .comma: ","
            case .period: "."
            case .question: "?"
            case .line: "\n"
            case .paragraph: "\n\n"
            }
        }

        var needsPrecedingWord: Bool {
            switch self {
            case .line, .paragraph: false
            default: true
            }
        }

        var startsSentence: Bool {
            self != .comma
        }
    }

    private static let phrases: [(words: [String], symbol: Symbol)] = [
        (["full", "stop"], .period),
        (["question", "mark"], .question),
        (["new", "paragraph"], .paragraph),
        (["new", "line"], .line),
        (["neuer", "absatz"], .paragraph),
        (["neue", "zeile"], .line),
        (["comma"], .comma),
        (["komma"], .comma),
        (["period"], .period),
        (["punkt"], .period),
        (["fragezeichen"], .question),
    ]

    private static let blockingPredecessors: Set<String> = [
        "the", "a", "an", "this", "that", "these", "those", "my", "your", "our", "no", "of", "word", "long", "short", "same", "last", "next",
        "der", "die", "das", "den", "dem", "ein", "eine", "einen", "einem", "dieser", "diese", "diesem", "kein", "keinen",
        "zum", "am", "bis", "auf", "für", "wort",
    ]
    private static let joiners: Set<String> = ["underscore", "unterstrich"]
    private static let quoteCharacters = CharacterSet(charactersIn: "\"\u{201C}\u{201D}\u{201E}\u{00AB}\u{00BB}")

    static func apply(to text: String) -> String {
        let tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var output = ""
        var separator = ""
        var capitalizeNext = false
        var index = 0
        while index < tokens.count {
            if let match = command(at: index, in: tokens) {
                output = trimmedTrailingPunctuation(output, symbol: match.symbol)
                output += match.symbol.text
                separator = match.symbol == .line || match.symbol == .paragraph ? "" : " "
                capitalizeNext = match.symbol.startsSentence
                index += match.length
                continue
            }
            if joiners.contains(tokens[index].lowercased()), !output.isEmpty, index + 1 < tokens.count {
                output += "_" + tokens[index + 1]
                separator = " "
                index += 2
                continue
            }
            output += separator + (capitalizeNext ? capitalizingStart(tokens[index]) : tokens[index])
            separator = " "
            capitalizeNext = false
            index += 1
        }
        return output
    }

    private static func command(at index: Int, in tokens: [String]) -> (symbol: Symbol, length: Int)? {
        for phrase in phrases {
            let end = index + phrase.words.count
            guard end <= tokens.count else { continue }
            let spoken = tokens[index..<end].map { WordTokens.stripEdges($0).lowercased() }
            guard spoken == phrase.words else { continue }
            guard isStandalone(phrase.symbol, spokenWord: phrase.words[0], range: index..<end, in: tokens) else { continue }
            return (phrase.symbol, phrase.words.count)
        }
        return nil
    }

    private static func isStandalone(_ symbol: Symbol, spokenWord: String, range: Range<Int>, in tokens: [String]) -> Bool {
        let previous = range.lowerBound > 0 ? tokens[range.lowerBound - 1] : nil
        let next = range.upperBound < tokens.count ? tokens[range.upperBound] : nil
        if symbol.needsPrecedingWord, previous == nil { return false }
        let neighbors = [previous, next].compactMap { $0 } + tokens[range]
        if neighbors.contains(where: { $0.rangeOfCharacter(from: quoteCharacters) != nil }) { return false }
        let previousWord = previous.map { WordTokens.stripEdges($0).lowercased() }
        let nextWord = next.map { WordTokens.stripEdges($0).lowercased() }
        if let previousWord, blockingPredecessors.contains(previousWord) { return false }
        if nextWord == "of" || nextWord == "von" { return false }
        if spokenWord == "komma", let previousWord, let nextWord, NumberWords.isNumber(previousWord), NumberWords.isNumber(nextWord) { return false }
        if spokenWord == "punkt", let nextWord, NumberWords.isNumber(nextWord) { return false }
        return true
    }

    private static func trimmedTrailingPunctuation(_ text: String, symbol: Symbol) -> String {
        guard symbol.needsPrecedingWord else { return text }
        var trimmed = text
        while let last = trimmed.last, ",.;:!?".contains(last) { trimmed.removeLast() }
        return trimmed
    }

    private static func capitalizingStart(_ word: String) -> String {
        guard let first = word.first else { return word }
        return first.uppercased() + word.dropFirst()
    }
}
