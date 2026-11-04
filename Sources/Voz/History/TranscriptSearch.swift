import Foundation
import GRDB

struct TranscriptSearch: Equatable {
    static let indexTable = "transcript_search"
    static let trigramLength = 3
    static let fuzzyCandidates = 300
    static let fuzzyMinimumShare = 0.6

    var indexedTerms: [String] = []
    var shortTerms: [String] = []
    var days: DateInterval?

    var isEmpty: Bool { indexedTerms.isEmpty && shortTerms.isEmpty && days == nil }

    init(_ query: String, now: Date = Date(), calendar: Calendar = .current) {
        for term in query.split(whereSeparator: \.isWhitespace).map(String.init) {
            if let days = Self.days(named: term, now: now, calendar: calendar) {
                self.days = days
            } else if term.unicodeScalars.count >= Self.trigramLength {
                indexedTerms.append(term)
            } else {
                shortTerms.append(term)
            }
        }
    }

    private static func days(named word: String, now: Date, calendar: Calendar) -> DateInterval? {
        let offset: Int
        switch word.lowercased() {
        case "today": offset = 0
        case "yesterday": offset = -1
        default: return nil
        }
        guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { return nil }
        return calendar.dateInterval(of: .day, for: day)
    }

    var allTermsPattern: String? {
        indexedTerms.isEmpty ? nil : indexedTerms.map(Self.phrase).joined(separator: " AND ")
    }

    var trigrams: Set<String> {
        Set(indexedTerms.flatMap { Self.trigrams(of: $0) })
    }

    var anyTrigramPattern: String? {
        let trigrams = trigrams
        return trigrams.isEmpty ? nil : trigrams.sorted().map(Self.phrase).joined(separator: " OR ")
    }

    func fuzzyShare(of record: TranscriptRecord) -> Double {
        let wanted = trigrams
        guard !wanted.isEmpty else { return 0 }
        let present = Set(Self.trigrams(of: "\(record.finalText) \(record.appName ?? "")"))
        return Double(wanted.intersection(present).count) / Double(wanted.count)
    }

    static func trigrams(of text: String) -> [String] {
        let scalars = Array(fold(text).unicodeScalars)
        guard scalars.count >= trigramLength else { return [] }
        return (0...(scalars.count - trigramLength)).compactMap { start in
            let window = scalars[start..<(start + trigramLength)]
            guard !window.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) }) else { return nil }
            var trigram = String.UnicodeScalarView()
            trigram.append(contentsOf: window)
            return String(trigram)
        }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static func phrase(_ term: String) -> String {
        "\"\(term.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
