import Testing
@testable import Voz

struct NoteMarkdownTests {
    private func kinds(_ text: String) -> [NoteMarkdown.Kind] {
        NoteMarkdown.spans(in: text).map(\.kind)
    }

    @Test func findsBoldAndCodeInsideALine() {
        #expect(kinds("ship **Friday**") == [.bold, .marker, .marker])
        #expect(kinds("run `voz dev`") == [.code, .marker, .marker])
        #expect(kinds("- item").isEmpty)
        #expect(NoteMarkdown.lines(in: "#nospace").isEmpty)
    }

    @Test func togglesTheCheckboxUnderTheClick() {
        let text = "Notes\n- [ ] Ship it"
        #expect(NoteMarkdown.toggleCheckbox(in: text, at: 9) == "Notes\n- [x] Ship it")
        #expect(NoteMarkdown.toggleCheckbox(in: "- [x] Ship it", at: 3) == "- [ ] Ship it")
        #expect(NoteMarkdown.toggleCheckbox(in: text, at: 2) == nil)
    }

    @Test func readsHeadingsAndNestedItems() {
        let lines = NoteMarkdown.lines(in: "## Plan\n- one\n  - two\n\t- [x] done\n3. three\nplain")
        #expect(lines.map(\.kind) == [.heading(2), .bullet, .bullet, .checkbox(checked: true), .numbered])
        #expect(lines.map(\.depth) == [0, 0, 1, 1, 0])
        #expect(lines[2].prefix.location == 14 && lines[2].prefix.length == 4)
        #expect(lines[4].hidden.length == 0)
        #expect(NoteMarkdown.lines(in: "## ").isEmpty)
    }

    @Test func findsTheItemOnALine() {
        let text = "intro\n- item"
        #expect(NoteMarkdown.line(at: 10, in: text)?.kind == .bullet)
        #expect(NoteMarkdown.line(at: 2, in: text) == nil)
    }

    @Test func rendersBulletsAndBoxesInPlaceOfMarks() {
        #expect(NoteMarkdown.rendered("### Next\n- **Ship** it\n- [ ] Write\n2. Review") == "Next\n• Ship it\n☐ Write\n2. Review")
    }

    @Test func collapsedNotesShowTheirLastTwoLines() {
        #expect(NoteMarkdown.lastLines(of: "# Sync\n- one\n\n  - two  \n", count: 2) == "- one\n- two")
        #expect(NoteMarkdown.lastLines(of: "only", count: 2) == "only")
        #expect(NoteMarkdown.lastLines(of: "\n \n", count: 2) == "")
    }

    @Test func plainTextDropsMarksAndJoinsLines() {
        let summary = "### Ship Friday\n\n- Milan owns the **changelog**\n- [ ] Write `notes`\n1. Review"
        #expect(NoteMarkdown.plain(summary) == "Ship Friday · Milan owns the changelog · Write notes · Review")
        #expect(NoteMarkdown.plain("#hashtag stays") == "#hashtag stays")
    }
}
