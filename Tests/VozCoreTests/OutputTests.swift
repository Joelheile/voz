import Testing
@testable import VozCore

@Suite struct OutputTests {
    @Test func restoresWhenPasteboardIsUntouched() {
        #expect(ClipboardRestoreGuard.shouldRestore(changeCountAtWrite: 7, currentChangeCount: 7))
    }

    @Test func skipsRestoreWhenUserCopiedSomethingElse() {
        #expect(!ClipboardRestoreGuard.shouldRestore(changeCountAtWrite: 7, currentChangeCount: 8))
    }

    @Test func restoreOnlyWhenPastingWithoutCopy() {
        var settings = OutputSettings()
        #expect(!settings.needsClipboardRestore)
        settings.copyToClipboard = false
        #expect(settings.needsClipboardRestore)
        settings.pasteIntoActiveApp = false
        #expect(!settings.needsClipboardRestore)
    }
}
