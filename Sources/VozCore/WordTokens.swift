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
