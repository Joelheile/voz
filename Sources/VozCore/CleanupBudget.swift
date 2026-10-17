public enum CleanupBudget {
    public static let total = Duration.milliseconds(1500)
    public static let segmentTimeout = Duration.milliseconds(4000)
    public static let minimumChunkWindow = Duration.milliseconds(600)
    public static let tokensPerWord = 3
    public static let tokenAllowance = 48
    public static let maxTokens = 512

    public static func maxResponseTokens(forWords words: Int) -> Int {
        min(maxTokens, tokensPerWord * max(words, 0) + tokenAllowance)
    }
}

public extension Duration {
    var wholeMilliseconds: Int {
        Int(components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000)
    }
}
