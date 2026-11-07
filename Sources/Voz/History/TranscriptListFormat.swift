import Foundation

enum RecentTime {
    static func label(for date: Date, now: Date, calendar: Calendar = .current) -> String {
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

    static func clock(for date: Date, calendar: Calendar = .current) -> String {
        date.formatted(formatStyle(calendar).hour().minute())
    }

    static func dayLabel(for day: Date, now: Date, calendar: Calendar = .current) -> String {
        let weekday = day.formatted(formatStyle(calendar).weekday(.abbreviated))
        let date = calendar.dateComponents([.day, .month, .year], from: day)
        let dayAndMonth = "\(weekday), \(date.day ?? 0).\(date.month ?? 0)"
        let sameYear = calendar.isDate(day, equalTo: now, toGranularity: .year)
        return sameYear ? dayAndMonth : "\(dayAndMonth).\((date.year ?? 0) % 100)"
    }

    private static func daysBetween(_ date: Date, _ now: Date, _ calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
    }

    private static func formatStyle(_ calendar: Calendar) -> Date.FormatStyle {
        Date.FormatStyle(locale: calendar.locale ?? .current, calendar: calendar, timeZone: calendar.timeZone)
    }
}

enum TranscriptSnippet {
    private static let lead = 20
    private static let matchOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    static func ranges(of query: String, in text: String) -> [Range<String.Index>] {
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

    static func text(_ text: String, around query: String) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        guard let firstMatch = ranges(of: query, in: flat).first?.lowerBound, flat.distance(from: flat.startIndex, to: firstMatch) > lead else { return flat }
        let windowStart = flat.index(firstMatch, offsetBy: -lead)
        let wordStart = flat[windowStart..<firstMatch].firstIndex(where: \.isWhitespace).map { flat.index(after: $0) } ?? windowStart
        return "… " + flat[wordStart...]
    }
}

/// The days that have a transcript, so stepping skips the empty ones
struct TranscriptDays: Equatable, Sendable {
    private let ascending: [Date]
    private let lookup: Set<Date>

    init(_ days: some Sequence<Date> = []) {
        lookup = Set(days)
        ascending = lookup.sorted()
    }

    var oldest: Date? { ascending.first }

    func contains(_ day: Date) -> Bool { lookup.contains(day) }

    func earlier(than day: Date) -> Date? {
        ascending.last { $0 < day }
    }

    func later(than day: Date) -> Date? {
        ascending.first { $0 > day }
    }
}

enum CalendarMonth {
    private static let cellCount = 42

    static func start(of date: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? date
    }

    /// Six weeks of cells, starting on the user's first weekday. `nil` cells fall outside the month.
    static func cells(of month: Date, calendar: Calendar = .current) -> [Date?] {
        let first = start(of: month, calendar: calendar)
        let dayCount = calendar.range(of: .day, in: .month, for: first)?.count ?? 0
        let blanks = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let days = (0..<dayCount).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
        let cells: [Date?] = Array(repeating: nil, count: blanks) + days
        return cells + Array(repeating: nil, count: cellCount - cells.count)
    }
}
