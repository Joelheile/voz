import Foundation

public enum CleanupOutput {
    private static let quotePairs: [(Character, Character)] = [("\"", "\""), ("\u{201C}", "\u{201D}"), ("\u{201E}", "\u{201C}"), ("\u{00AB}", "\u{00BB}")]

    public static func sanitized(_ output: String, raw: String) -> String {
        var text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.replacingOccurrences(of: "</?transcript>", with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = text.first, let last = text.last, text.count > 1 else { return text }
        let rawHasQuotes = quotePairs.contains { raw.contains($0.0) || raw.contains($0.1) }
        guard !rawHasQuotes, quotePairs.contains(where: { $0.0 == first && $0.1 == last }) else { return text }
        return String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
