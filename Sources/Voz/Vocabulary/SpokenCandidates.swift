enum SpokenCandidates {
    static let minimumSpelledLetters = 3

    static func find(in text: String, isKnownWord: (String) -> Bool) -> [VocabularyCandidate] {
        let spelled = spelledWords(in: text.split(whereSeparator: \.isWhitespace).map(String.init))
        let corrected = corrections(in: WordTokens.split(text))
        return (spelled + corrected).filter { EditLearner.isWorthLearning($0, isKnownWord: isKnownWord) }
    }

    private static func corrections(in tokens: [String]) -> [VocabularyCandidate] {
        zip(tokens, zip(tokens.dropFirst(), tokens.dropFirst(2))).compactMap { not, pair in
            not.lowercased() == "not" ? VocabularyCandidate(word: pair.1, heardAs: pair.0) : nil
        }
    }

    private static func spelledWords(in tokens: [String]) -> [VocabularyCandidate] {
        var candidates: [VocabularyCandidate] = []
        var letters: [String] = []
        func flush() {
            if letters.count >= minimumSpelledLetters {
                let word = letters.joined().lowercased().capitalized
                candidates.append(VocabularyCandidate(word: word, heardAs: letters.joined(separator: " ")))
            }
            letters = []
        }
        for token in tokens {
            let letter = WordTokens.stripEdges(token)
            guard letter.count == 1, letter.first?.isLetter == true else {
                flush()
                continue
            }
            letters.append(letter)
            if letter != token { flush() }
        }
        flush()
        return candidates
    }
}
