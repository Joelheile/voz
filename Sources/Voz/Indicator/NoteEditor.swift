import AppKit
import SwiftUI

/// A plain-text note editor that styles its Markdown as you type, and toggles checkboxes on click
struct NoteEditor: NSViewRepresentable {
    @Binding var text: String
    var onEdit: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NoteTextView(usingTextLayoutManager: false)
        textView.textContainer?.replaceLayoutManager(NoteLayout())
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.typingAttributes = NoteStyle.body
        textView.string = text
        NoteStyle.apply(to: textView)

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets.bottom = NoteStyle.fade
        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scroll.documentView as? NoteTextView else { return }
        guard textView.string != text else { return }
        textView.string = text
        NoteStyle.apply(to: textView)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteEditor

        init(_ parent: NoteEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            NoteStyle.apply(to: textView)
            parent.text = textView.string
            parent.onEdit()
        }

        /// Bold and code show their marks on the line you are editing
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            NoteStyle.apply(to: textView)
        }

        /// The cursor skips over hidden marks, so it always sits where the text starts
        func textView(
            _ textView: NSTextView, willChangeSelectionFromCharacterRange old: NSRange, toCharacterRange new: NSRange
        ) -> NSRange {
            guard new.length == 0, let line = NoteMarkdown.line(at: new.location, in: textView.string) else { return new }
            let hidden = line.hidden
            guard new.location >= hidden.location, new.location < NSMaxRange(hidden) else { return new }
            if new.location < old.location, old.location == NSMaxRange(hidden), hidden.location > 0 {
                return NSRange(location: hidden.location - 1, length: 0)
            }
            return NSRange(location: NSMaxRange(hidden), length: 0)
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)): NoteLists.continueList(in: textView)
            case #selector(NSResponder.deleteBackward(_:)): NoteLists.removeMark(in: textView)
            case #selector(NSResponder.insertTab(_:)): NoteLists.indent(in: textView)
            case #selector(NSResponder.insertBacktab(_:)): NoteLists.outdent(in: textView)
            default: false
            }
        }
    }
}

private final class NoteTextView: NSTextView {
    /// A click on a drawn box ticks it
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let index = characterIndexForInsertion(at: point)
        guard let line = NoteMarkdown.line(at: index, in: string), case .checkbox = line.kind,
              point.x - textContainerOrigin.x < NoteStyle.textStart(line),
              let toggled = NoteMarkdown.toggleCheckbox(in: string, at: line.prefix.location + line.indent + 3)
        else { return super.mouseDown(with: event) }
        let selection = selectedRanges
        guard shouldChangeText(in: NSRange(location: 0, length: (string as NSString).length), replacementString: toggled) else { return }
        string = toggled
        didChangeText()
        selectedRanges = selection
    }
}

/// Starts the next bullet or checkbox when you press Return, and ends the list on an empty one
private enum NoteLists {
    private static let item = try! NSRegularExpression(pattern: "^([ \\t]*)([-*] \\[[ xX]\\] |[-*] |(\\d+)\\. )(.*)$")

    @MainActor
    static func continueList(in textView: NSTextView) -> Bool {
        let text = textView.string as NSString
        let cursor = textView.selectedRange()
        guard cursor.length == 0 else { return false }
        let line = text.lineRange(for: NSRange(location: cursor.location, length: 0))
        let content = text.substring(with: line).trimmingCharacters(in: .newlines)
        guard let match = item.firstMatch(in: content, range: NSRange(location: 0, length: (content as NSString).length)) else { return false }
        let indent = (content as NSString).substring(with: match.range(at: 1))
        let marker = (content as NSString).substring(with: match.range(at: 2))
        let rest = (content as NSString).substring(with: match.range(at: 4))
        if rest.isEmpty {
            if !indent.isEmpty { return outdent(in: textView) }
            textView.insertText("", replacementRange: NSRange(location: line.location, length: (content as NSString).length))
            return true
        }
        var next = marker.contains("[") ? "- [ ] " : marker
        if match.range(at: 3).location != NSNotFound, let number = Int((content as NSString).substring(with: match.range(at: 3))) {
            next = "\(number + 1). "
        }
        textView.insertText("\n\(indent)\(next)", replacementRange: cursor)
        return true
    }

    /// Backspace right after a hidden mark takes the mark away: a nested item moves out a level, others turn into text
    @MainActor
    static func removeMark(in textView: NSTextView) -> Bool {
        let cursor = textView.selectedRange()
        guard cursor.length == 0, let line = NoteMarkdown.line(at: cursor.location, in: textView.string),
              line.kind != .numbered, cursor.location == NSMaxRange(line.prefix)
        else { return false }
        if line.depth > 0 { return outdent(in: textView) }
        textView.insertText("", replacementRange: line.prefix)
        return true
    }

    @MainActor
    static func indent(in textView: NSTextView) -> Bool {
        guard let line = listItem(in: textView) else { return false }
        textView.insertText(unit, replacementRange: NSRange(location: line.prefix.location, length: 0))
        return true
    }

    @MainActor
    static func outdent(in textView: NSTextView) -> Bool {
        guard let line = listItem(in: textView) else { return false }
        guard line.indent > 0 else { return true }
        let tab = (textView.string as NSString).character(at: line.prefix.location) == 9
        let length = tab ? 1 : min(unit.count, line.indent)
        textView.insertText("", replacementRange: NSRange(location: line.prefix.location, length: length))
        return true
    }

    private static let unit = "  "

    @MainActor
    private static func listItem(in textView: NSTextView) -> NoteMarkdown.Line? {
        guard let line = NoteMarkdown.line(at: textView.selectedRange().location, in: textView.string),
              !(line.kind.isHeading)
        else { return nil }
        return line
    }
}

extension NoteMarkdown.Line.Kind {
    var isHeading: Bool {
        if case .heading = self { true } else { false }
    }
}

@MainActor
enum NoteStyle {
    nonisolated static let size: CGFloat = 14
    /// How far each list level moves in, with room for its bullet
    nonisolated static let step: CGFloat = 22
    /// How far text fades out at the bottom of a note, so lines scroll away under the edge
    nonisolated static let fade: CGFloat = 12

    static var body: [NSAttributedString.Key: Any] {
        [.font: font(size), .foregroundColor: NSColor(Theme.ink), .paragraphStyle: paragraph()]
    }

    private static func paragraph(first: CGFloat = 0, rest: CGFloat = 0, before: CGFloat = 0, after: CGFloat = 0) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        style.firstLineHeadIndent = first
        style.headIndent = rest
        style.paragraphSpacingBefore = before
        style.paragraphSpacing = after
        return style
    }

    /// San Francisco reads easier than Geist in long notes and has every glyph a note might hold
    nonisolated static func font(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        .systemFont(ofSize: size, weight: weight)
    }

    /// Where the text of a heading or list item starts
    nonisolated static func textStart(_ line: NoteMarkdown.Line) -> CGFloat {
        line.kind.isHeading ? 0 : CGFloat(line.depth + 1) * step
    }

    static func apply(to textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let editing = (textView.string as NSString).lineRange(for: textView.selectedRange())
        storage.beginEditing()
        style(storage, editing: editing)
        storage.endEditing()
        textView.typingAttributes = body
    }

    static func styled(_ text: String) -> NSAttributedString {
        let styled = NSMutableAttributedString(string: text)
        style(styled, editing: nil)
        return styled
    }

    private static func style(_ text: NSMutableAttributedString, editing: NSRange?) {
        let string = text.string as NSString
        text.setAttributes(body, range: NSRange(location: 0, length: text.length))
        for line in NoteMarkdown.lines(in: text.string) {
            let paragraph = string.paragraphRange(for: line.prefix)
            text.addAttribute(.noteHidden, value: true, range: line.hidden)
            switch line.kind {
            case .heading(let level):
                let size: CGFloat = [20, 17, 15][level - 1]
                text.addAttributes([
                    .font: font(size, weight: level == 1 ? .bold : .semibold),
                    .foregroundColor: NSColor(level == 3 ? Theme.inkSecondary : Theme.ink),
                    .paragraphStyle: Self.paragraph(before: line.prefix.location == 0 ? 0 : 10, after: 2),
                ], range: paragraph)
            case .numbered:
                let number = string.substring(with: line.prefix).trimmingCharacters(in: .whitespaces) + " "
                let width = (number as NSString).size(withAttributes: [.font: font(size)]).width
                let start = textStart(line)
                text.addAttribute(.paragraphStyle, value: Self.paragraph(first: start - width, rest: start, after: 6), range: paragraph)
                let marks = NSRange(location: NSMaxRange(line.hidden), length: line.prefix.length - line.indent)
                text.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: marks)
            case .bullet, .checkbox:
                let start = textStart(line)
                text.addAttribute(.paragraphStyle, value: Self.paragraph(first: start, rest: start, after: 6), range: paragraph)
                text.addAttribute(.noteMark, value: NoteMark(line), range: line.prefix)
                if case .checkbox(checked: true) = line.kind {
                    let rest = NSRange(location: NSMaxRange(line.prefix), length: NSMaxRange(paragraph) - NSMaxRange(line.prefix))
                    text.addAttributes([.foregroundColor: NSColor.tertiaryLabelColor, .strikethroughStyle: NSUnderlineStyle.single.rawValue], range: rest)
                }
            }
        }
        for span in NoteMarkdown.spans(in: text.string) {
            switch span.kind {
            case .bold:
                text.addAttribute(.font, value: font(size, weight: .semibold), range: span.range)
            case .code:
                text.addAttributes([.font: NSFont.monospacedSystemFont(ofSize: size - 1, weight: .regular), .backgroundColor: NSColor(Theme.selected)], range: span.range)
            case .marker where text.attribute(.noteHidden, at: span.range.location, effectiveRange: nil) == nil:
                // Bold and code marks show only on the line you edit, so you can see what you change
                if let editing, NSIntersectionRange(editing, span.range).length > 0 {
                    text.addAttribute(.foregroundColor, value: NSColor(Theme.inkTertiary), range: span.range)
                } else {
                    text.addAttribute(.noteHidden, value: true, range: span.range)
                }
            default:
                break
            }
        }
    }
}

extension NSAttributedString.Key {
    /// Characters the note keeps in its text but doesn't draw, such as `## ` and `- `
    static let noteHidden = NSAttributedString.Key("VozNoteHidden")
    /// A bullet or box the note draws in place of a list mark
    static let noteMark = NSAttributedString.Key("VozNoteMark")
}

final class NoteMark: NSObject {
    let line: NoteMarkdown.Line
    init(_ line: NoteMarkdown.Line) { self.line = line }
}

/// Lays out a note without its hidden marks, and draws bullets and boxes in the space before each item
private final class NoteLayout: NSLayoutManager, NSLayoutManagerDelegate {
    override init() {
        super.init()
        delegate = self
    }

    required init?(coder: NSCoder) { nil }

    func layoutManager(
        _ layoutManager: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
        properties: UnsafePointer<NSLayoutManager.GlyphProperty>, characterIndexes: UnsafePointer<Int>,
        font: NSFont, forGlyphRange range: NSRange
    ) -> Int {
        guard let storage = textStorage else { return 0 }
        let count = range.length
        var hidden = false
        let changed = UnsafeMutablePointer<NSLayoutManager.GlyphProperty>.allocate(capacity: count)
        defer { changed.deallocate() }
        for index in 0..<count {
            changed[index] = properties[index]
            if storage.attribute(.noteHidden, at: characterIndexes[index], effectiveRange: nil) != nil {
                changed[index] = .null
                hidden = true
            }
        }
        guard hidden else { return 0 }
        setGlyphs(glyphs, properties: changed, characterIndexes: characterIndexes, font: font, forGlyphRange: range)
        return count
    }

    override func drawBackground(forGlyphRange glyphs: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphs, at: origin)
        guard let storage = textStorage else { return }
        let characters = characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        storage.enumerateAttribute(.noteMark, in: characters) { value, range, _ in
            guard let mark = value as? NoteMark else { return }
            let glyph = glyphIndexForCharacter(at: range.location)
            let fragment = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let font = NoteStyle.font(NoteStyle.size)
            let center = NSPoint(
                x: origin.x + NoteStyle.textStart(mark.line) - NoteStyle.step / 2 - 1,
                y: origin.y + fragment.minY + font.ascender - (mark.line.kind == .bullet ? font.xHeight : font.capHeight) / 2
            )
            draw(mark.line.kind, depth: mark.line.depth, at: center)
        }
    }

    /// Marks in the accent color, like the text cursor, so lists read at a glance
    private func draw(_ kind: NoteMarkdown.Line.Kind, depth: Int, at center: NSPoint) {
        let accent = NSColor.controlAccentColor
        switch kind {
        case .checkbox(let checked):
            let box = NSRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14)
            guard checked else {
                let outline = NSBezierPath(roundedRect: box.insetBy(dx: 0.625, dy: 0.625), xRadius: 3.5, yRadius: 3.5)
                NSColor.tertiaryLabelColor.setStroke()
                outline.lineWidth = 1.25
                return outline.stroke()
            }
            accent.setFill()
            NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
            let tick = NSBezierPath()
            tick.move(to: NSPoint(x: center.x - 3.5, y: center.y + 0.25))
            tick.line(to: NSPoint(x: center.x - 1, y: center.y + 2.75))
            tick.line(to: NSPoint(x: center.x + 3.5, y: center.y - 2.5))
            tick.lineWidth = 1.5
            tick.lineCapStyle = .round
            tick.lineJoinStyle = .round
            NSColor.white.setStroke()
            tick.stroke()
        default:
            // A dot at the top level and a ring below it, so nesting reads at a glance
            let radius: CGFloat = 2.5
            let dot = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            accent.set()
            if depth % 2 == 0 {
                dot.fill()
            } else {
                dot.lineWidth = 1.25
                dot.stroke()
            }
        }
    }
}

/// The last lines of a note, styled like the editor, for the note while it is collapsed under the notch
struct NoteSnippet: NSViewRepresentable {
    let text: String
    static let lines = 2

    func makeNSView(context: Context) -> NSTextField {
        let label = NSTextField(labelWithAttributedString: NSAttributedString())
        label.maximumNumberOfLines = Self.lines
        label.lineBreakMode = .byTruncatingTail
        label.cell?.truncatesLastVisibleLine = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    func updateNSView(_ label: NSTextField, context: Context) {
        label.attributedStringValue = NoteStyle.styled(NoteMarkdown.rendered(NoteMarkdown.lastLines(of: text, count: Self.lines)))
    }
}
