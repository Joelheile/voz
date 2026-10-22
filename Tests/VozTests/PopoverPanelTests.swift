import Testing
@testable import Voz

@MainActor
@Test func popoverPanelHandlesEditShortcutsWithoutAnEditMenu() {
    let actions = editActionsHandled(byPanelFor: [
        ("x", .command), ("c", .command), ("v", .command), ("a", .command),
        ("z", .command), ("z", [.command, .shift]), ("v", [.command, .option]),
    ])
    #expect(actions == ["cut", "copy", "paste", "selectAll", "undo", "redo"])
}
