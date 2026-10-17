import Foundation

public enum VocabularyCasing {
    public static func apply(_ vocabulary: [String], to text: String) -> String {
        vocabulary.reduce(text) { current, word in
            let escaped = NSRegularExpression.escapedPattern(for: word)
            let pattern = "(?<![\\p{L}\\p{N}])\(escaped)(?![\\p{L}\\p{N}])"
            return current.replacingOccurrences(
                of: pattern,
                with: NSRegularExpression.escapedTemplate(for: word),
                options: [.regularExpression, .caseInsensitive]
            )
        }
    }
}
