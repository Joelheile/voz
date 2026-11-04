import Foundation

/// The few Markdown marks a note styles as you type: headings, lists, checkboxes, bold and code
enum NoteMarkdown {
    /// Bold or code inside a line, and the marks around it
    enum Kind: Equatable {
        case marker
        case bold
        case code
    }

    struct Span: Equatable {
        let kind: Kind
        let range: NSRange
    }

    private static let bold = try! NSRegularExpression(pattern: "(\\*\\*)(?=\\S)(.+?)(?<=\\S)(\\*\\*)")
    private static let code = try! NSRegularExpression(pattern: "(`)([^`\\n]+)(`)")

    static func spans(in text: String) -> [Span] {
        let whole = NSRange(text.startIndex..., in: text)
        return [(bold, Kind.bold), (code, Kind.code)].flatMap { expression, kind in
            expression.matches(in: text, range: whole).flatMap { match in
                [
                    Span(kind: kind, range: match.range(at: 2)),
                    Span(kind: .marker, range: match.range(at: 1)),
                    Span(kind: .marker, range: match.range(at: 3)),
                ]
            }
        }
    }

    /// A heading or list item, which the editor draws without its marks
    struct Line: Equatable {
        enum Kind: Equatable {
            case heading(Int)
            case bullet
            case checkbox(checked: Bool)
            case numbered
        }

        let kind: Kind
        /// How far the item is nested: a tab or two spaces per level
        let depth: Int
        /// The indent and marks before the text, such as `  - [ ] ` or `## `
        let prefix: NSRange
        let indent: Int

        /// What the editor hides. Numbers stay, so you can see the order.
        var hidden: NSRange {
            kind == .numbered ? NSRange(location: prefix.location, length: indent) : prefix
        }
    }

    private static let line = try! NSRegularExpression(
        pattern: "^(?:(#{1,3}) +(?=\\S)|([ \\t]*)(?:[-*] \\[([ xX])\\] |([-*]) |\\d+\\. ))", options: .anchorsMatchLines
    )

    static func lines(in text: String) -> [Line] {
        let string = text as NSString
        return line.matches(in: text, range: NSRange(location: 0, length: string.length)).map { match in
            let hashes = match.range(at: 1)
            if hashes.location != NSNotFound {
                return Line(kind: .heading(hashes.length), depth: 0, prefix: match.range, indent: 0)
            }
            let indent = string.substring(with: match.range(at: 2))
            let depth = indent.reduce(0) { $0 + ($1 == "\t" ? 2 : 1) } / 2
            let kind: Line.Kind = if match.range(at: 3).location != NSNotFound {
                .checkbox(checked: string.substring(with: match.range(at: 3)) != " ")
            } else if match.range(at: 4).location != NSNotFound {
                .bullet
            } else {
                .numbered
            }
            return Line(kind: kind, depth: depth, prefix: match.range, indent: indent.utf16.count)
        }
    }

    /// The heading or list item on the line that holds `location`
    static func line(at location: Int, in text: String) -> Line? {
        let start = (text as NSString).lineRange(for: NSRange(location: location, length: 0)).location
        return lines(in: text).first { $0.prefix.location == start }
    }

    /// Flips the checkbox on the line that holds `location`, or returns nil when there is none
    static func toggleCheckbox(in text: String, at location: Int) -> String? {
        guard let line = line(at: location, in: text), case .checkbox(let checked) = line.kind else { return nil }
        let box = NSRange(location: line.prefix.location + line.indent + 2, length: 3)
        return (text as NSString).replacingCharacters(in: box, with: checked ? "[ ]" : "[x]")
    }

    private static let lineMarks = try! NSRegularExpression(pattern: "^[ \\t]*(#{1,3} +|([-*]|\\d+\\.) (\\[[ xX]\\] )?)", options: .anchorsMatchLines)
    private static let inlineMarks = try! NSRegularExpression(pattern: "\\*\\*|`")

    /// The text without its marks, one line after another, such as for a summary in a history row
    static func plain(_ text: String) -> String {
        let withoutLineMarks = lineMarks.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        let bare = inlineMarks.stringByReplacingMatches(
            in: withoutLineMarks, range: NSRange(withoutLineMarks.startIndex..., in: withoutLineMarks), withTemplate: ""
        )
        return bare.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// The text as the editor shows it, with bullets and boxes in place of marks
    static func rendered(_ text: String) -> String {
        let result = NSMutableString(string: text)
        for line in lines(in: text).reversed() {
            let mark = switch line.kind {
            case .heading: ""
            case .bullet: "• "
            case .checkbox(let checked): checked ? "☑ " : "☐ "
            case .numbered: (text as NSString).substring(with: line.prefix).trimmingCharacters(in: .whitespaces) + " "
            }
            result.replaceCharacters(in: line.prefix, with: mark)
        }
        return inlineMarks.stringByReplacingMatches(in: result as String, range: NSRange(location: 0, length: result.length), withTemplate: "")
    }

    /// The last lines that hold text, such as for a note collapsed under the notch
    static func lastLines(of text: String, count: Int) -> String {
        text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .suffix(count)
            .joined(separator: "\n")
    }
}
