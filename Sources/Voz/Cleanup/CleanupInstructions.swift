import VozCore

enum CleanupInstructions {
    static func transcriptPrompt(for text: String) -> String {
        "<transcript>\n\(text)\n</transcript>"
    }

    static let promptPrefix = "<transcript>\n"

    static func text(prompt: String, vocabulary: [String]) -> String {
        guard !vocabulary.isEmpty else { return prompt }
        return prompt + "\n\nPreferred spellings. If a word sounds like one of these, use this spelling: \(vocabulary.joined(separator: ", "))."
    }
}
