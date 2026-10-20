import Foundation

public enum SegmentJoiner {
    private static let sentenceEnders = CharacterSet(charactersIn: ".!?…:\n")
    private static let closers = CharacterSet(charactersIn: "\"\u{201D}\u{00BB}')]")

    public static func join(_ texts: [String]) -> String {
        texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    public static func join(cleaned: [String?], fallback: [String]) -> String {
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
