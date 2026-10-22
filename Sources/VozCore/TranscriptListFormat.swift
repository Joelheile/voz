import Foundation

public enum RecentTime {
    public static func label(for date: Date, now: Date, calendar: Calendar = .current) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "now" }
        if seconds < 3_600 { return "\(Int(seconds / 60))m" }
        let style = formatStyle(calendar)
        switch daysBetween(date, now, calendar) {
        case 0: return "\(Int(seconds / 3_600))h"
        case 1: return date.formatted(style.hour().minute())
        case 2..<7: return date.formatted(style.weekday(.abbreviated))
        default:
            let sameYear = calendar.isDate(date, equalTo: now, toGranularity: .year)
            return date.formatted(sameYear ? style.day().month(.abbreviated) : style.day().month(.abbreviated).year())
        }
    }

    public static func heading(for date: Date, now: Date, calendar: Calendar = .current) -> String? {
        switch daysBetween(date, now, calendar) {
        case ...0: nil
        case 1: "Yesterday"
        default: "Earlier"
        }
    }

    private static func daysBetween(_ date: Date, _ now: Date, _ calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
    }

    private static func formatStyle(_ calendar: Calendar) -> Date.FormatStyle {
        Date.FormatStyle(locale: calendar.locale ?? .current, calendar: calendar, timeZone: calendar.timeZone)
    }
}

public enum TranscriptSnippet {
    private static let lead = 20
    private static let matchOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    public static func ranges(of query: String, in text: String) -> [Range<String.Index>] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }
        var ranges: [Range<String.Index>] = []
        var searchStart = text.startIndex
        while let range = text.range(of: term, options: matchOptions, range: searchStart..<text.endIndex) {
            ranges.append(range)
            searchStart = range.upperBound
        }
        return ranges
    }

    public static func text(_ text: String, around query: String) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        guard let firstMatch = ranges(of: query, in: flat).first?.lowerBound, flat.distance(from: flat.startIndex, to: firstMatch) > lead else { return flat }
        let windowStart = flat.index(firstMatch, offsetBy: -lead)
        let wordStart = flat[windowStart..<firstMatch].firstIndex(where: \.isWhitespace).map { flat.index(after: $0) } ?? windowStart
        return "… " + flat[wordStart...]
    }
}
