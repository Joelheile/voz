import Foundation

public enum CleanupRejection: String, Sendable, Equatable {
    case empty
    case refusal
    case leakedTags
    case tooLong
    case lowOverlap
    case droppedWords
}

public enum CleanupGuard {
    public static let maxLengthRatio = 1.3
    public static let minSharedVocabulary = 0.6
    public static let minCoverageWithCorrections = 0.5
    public static let minCoverageWithoutCorrections = 0.7
    public static let correctionCountThatSkipsCoverage = 3

    private static let refusalPrefixes: [[String]] = [
        ["i'm", "sorry"], ["i", "am", "sorry"], ["i", "can't"], ["i", "cannot"], ["sure"], ["here", "is"], ["here's"],
        ["please", "provide"], ["entschuldigung"], ["ich", "kann"],
    ]
    private static let outputLabels = ["output:", "cleaned:"]
    private static let fillerAndCorrectionWords: Set<String> = [
        "um", "uh", "uhm", "umm", "erm", "ähm", "äh", "öhm", "like", "halt", "also", "sozusagen", "quasi",
        "no", "nein", "nee", "wait", "warte", "sorry", "mean",
    ]

    private static let spokenSymbolWords: Set<String> = ["dot", "at", "slash", "underscore", "dash", "colon"]

    public static func rejection(raw: String, cleaned: String) -> CleanupRejection? {
        let rawWords = WordTokens.alphanumeric(raw)
        let cleanedWords = WordTokens.alphanumeric(cleaned)
        guard !cleanedWords.isEmpty, !rawWords.isEmpty else { return .empty }
        if isRefusal(raw: raw, cleaned: cleaned) { return .refusal }
        if hasLeakedMarkup(raw: raw, cleaned: cleaned) { return .leakedTags }
        guard Double(cleanedWords.count) <= Double(rawWords.count) * maxLengthRatio else { return .tooLong }
        let rawVocabulary = Set(rawWords)
        let cleanedVocabulary = Set(cleanedWords)
        let comparable = cleanedWords.filter { !$0.contains(where: \.isNumber) }
        let shared = comparable.filter { rawVocabulary.contains($0) }.count
        if !comparable.isEmpty, Double(shared) / Double(comparable.count) < minSharedVocabulary { return .lowOverlap }
        let corrections = rawWords.filter { fillerAndCorrectionWords.contains($0) }.count
        guard corrections < correctionCountThatSkipsCoverage else { return nil }
        let expected = rawWords.filter { !fillerAndCorrectionWords.contains($0) && !spokenSymbolWords.contains($0) && !NumberWords.isNumber($0) }
        guard !expected.isEmpty else { return nil }
        let kept = expected.filter { cleanedVocabulary.contains($0) }.count
        let minimum = corrections == 0 ? minCoverageWithoutCorrections : minCoverageWithCorrections
        return Double(kept) / Double(expected.count) < minimum ? .droppedWords : nil
    }

    private static func isRefusal(raw: String, cleaned: String) -> Bool {
        let cleanedStart = leadingWords(cleaned)
        let rawStart = leadingWords(raw)
        return refusalPrefixes.contains { prefix in
            cleanedStart.starts(with: prefix) && !rawStart.starts(with: prefix)
        }
    }

    private static func leadingWords(_ text: String) -> [String] {
        WordTokens.normalized(text.replacingOccurrences(of: "\u{2019}", with: "'")).prefix(3).map { $0 }
    }

    private static func hasLeakedMarkup(raw: String, cleaned: String) -> Bool {
        if cleaned.contains("<"), !raw.contains("<") { return true }
        let lowered = cleaned.lowercased()
        let rawLowered = raw.lowercased()
        return outputLabels.contains { lowered.hasPrefix($0) && !rawLowered.hasPrefix($0) }
    }
}
