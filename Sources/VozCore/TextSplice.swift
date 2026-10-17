import Foundation

public struct TextEdit: Equatable, Sendable {
    public let utf8Range: Range<Int>
    public let replacement: String

    public init(utf8Range: Range<Int>, replacement: String) {
        self.utf8Range = utf8Range
        self.replacement = replacement
    }
}

public enum TextSplice {
    public static func apply(_ edits: [TextEdit], to text: String) -> String {
        var bytes = Array(text.utf8)
        var lowerLimit = bytes.count
        for edit in edits.sorted(by: { $0.utf8Range.lowerBound > $1.utf8Range.lowerBound }) {
            guard edit.utf8Range.upperBound <= lowerLimit, edit.utf8Range.upperBound <= bytes.count else { continue }
            bytes.replaceSubrange(edit.utf8Range, with: Array(edit.replacement.utf8))
            lowerLimit = edit.utf8Range.lowerBound
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
