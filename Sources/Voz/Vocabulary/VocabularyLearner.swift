struct VocabularyLearner: Sendable {
    typealias Hear = @Sendable (String) async -> String?

    let store: VocabularyStore
    let hear: Hear

    func consider(_ candidates: [VocabularyCandidate]) async {
        for candidate in candidates {
            do {
                guard try !store.contains(candidate.heardAs) else { continue }
                if try store.contains(candidate.word) {
                    try store.addRule(VocabularyRule(heard: candidate.heardAs, word: candidate.word))
                    Log.app.notice("Vocabulary rule added")
                    continue
                }
                guard try !store.knows(candidate.word) else { continue }
                let heard = await hear(candidate.word).map { WordTokens.split($0).joined(separator: " ") }
                try store.suggest(candidate.word, aliases: Self.aliases([candidate.heardAs, heard].compactMap { $0 }, of: candidate.word))
                Log.app.notice("Vocabulary suggestion added")
            } catch {
                Log.app.error("Vocabulary suggestion failed: \(error.localizedDescription, privacy: .private)")
            }
        }
    }

    func forget(_ edits: [VocabularyCandidate]) async {
        for edit in edits {
            do {
                try store.removeRule(VocabularyRule(heard: edit.word, word: edit.heardAs))
            } catch {
                Log.app.error("Vocabulary rule removal failed: \(error.localizedDescription, privacy: .private)")
            }
        }
    }

    private static func letters(_ text: String) -> String {
        WordTokens.alphanumeric(text).joined()
    }

    private static func aliases(_ heard: [String], of word: String) -> [String] {
        heard.reduce(into: []) { result, alias in
            let seen = [word] + result
            if !alias.isEmpty, !seen.contains(where: { letters($0) == letters(alias) }) { result.append(alias) }
        }
    }
}
