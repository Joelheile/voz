import Foundation

/// Drops words the microphone picked up from the speakers, by matching them against what the Mac played at about the same time
actor LiveEcho {
    static let window = 1.5
    private static let longestWait = Duration.seconds(10)
    private static let poll = Duration.milliseconds(200)

    private var played: [TimedWord] = []
    private var playedUntil = 0.0

    func heard(_ words: [TimedWord], until seconds: Double) {
        played += words
        playedUntil = max(playedUntil, seconds)
    }

    /// Call when the system audio has nothing more, so the microphone stops waiting for it
    func finish() {
        playedUntil = .infinity
    }

    /// Waits until the system audio caught up with these words, or 10 seconds, then removes the echo
    func removeEcho(from words: [TimedWord]) async -> [TimedWord] {
        guard let last = words.last else { return words }
        let deadline = ContinuousClock.now + Self.longestWait
        while playedUntil < last.end + Self.window, ContinuousClock.now < deadline {
            try? await Task.sleep(for: Self.poll)
        }
        return Self.remove(words, played: played.filter { $0.end >= words[0].start - Self.window })
    }

    /// A word is echo when the Mac played the same word within `window` seconds. A short word on its own stays,
    /// since "I", "so" or "yes" often overlap by chance when both people talk.
    static func remove(_ words: [TimedWord], played: [TimedWord]) -> [TimedWord] {
        let keys = words.map { key($0.text) }
        let echoed = words.indices.map { index in
            !keys[index].isEmpty && played.contains { key($0.text) == keys[index] && abs($0.start - words[index].start) <= window }
        }
        return words.indices.filter { index in
            guard echoed[index] else { return true }
            let besideEcho = (index > 0 && echoed[index - 1]) || (index + 1 < words.count && echoed[index + 1])
            return !besideEcho && keys[index].count <= 3
        }
        .map { words[$0] }
    }

    private static func key(_ word: String) -> String {
        word.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
