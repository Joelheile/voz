import Foundation

public enum SegmentJoiner {
    private static let sentenceEnders = CharacterSet(charactersIn: ".!?…:\n")
    private static let closers = CharacterSet(charactersIn: "\"\u{201D}\u{00BB}')]")

    public static func join(_ texts: [String], lowercaseContinuations: Bool) -> String {
        var joined = ""
        for text in texts.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }).filter({ !$0.isEmpty }) {
            guard !joined.isEmpty else {
                joined = text
                continue
            }
            let continues = lowercaseContinuations && !endsSentence(joined)
            joined += " " + (continues ? loweringFirstWord(text) : text)
        }
        return joined
    }

    public static func join(cleaned: [String?], fallback: [String], lowercaseContinuations: Bool) -> String {
        let chosen = fallback.indices.map { index in
            index < cleaned.count ? (cleaned[index] ?? fallback[index]) : fallback[index]
        }
        return join(chosen, lowercaseContinuations: lowercaseContinuations)
    }

    private static func endsSentence(_ text: String) -> Bool {
        let core = text.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: closers)
        guard let last = core.unicodeScalars.last else { return true }
        return sentenceEnders.contains(last)
    }

    private static func loweringFirstWord(_ text: String) -> String {
        let word = text.prefix { !$0.isWhitespace }
        let letters = word.filter(\.isLetter)
        guard letters.count > 1, word.first?.isUppercase == true,
              letters.dropFirst().allSatisfy(\.isLowercase),
              !(word.hasPrefix("I'") || word.hasPrefix("I\u{2019}"))
        else { return text }
        return word.prefix(1).lowercased() + text.dropFirst()
    }
}
