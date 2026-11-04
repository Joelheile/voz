import Testing
@testable import Voz

@Suite struct ScreenTextTests {
    @Test func secretsAreHiddenBeforeAnExtensionSeesThem() {
        let text = """
            key sk-proj-abcdefghijklmnop1234 and ghp_abcdefghijklmnopqrstuvwxyz123456
            password: hunter2
            card 4242 4242 4242 4242, IBAN DE89 3704 0044 0532 0130 00
            -----BEGIN PRIVATE KEY-----
            MIIEvQ
            -----END PRIVATE KEY-----
            see you at 1pm
            """
        let shown = Redaction.redact(text)
        for secret in ["sk-proj", "ghp_", "hunter2", "4242", "DE89", "MIIEvQ"] { #expect(!shown.contains(secret)) }
        #expect(shown.contains("see you at 1pm"))
    }

    @Test func windowTextReadsTopToBottomAndSkipsRepeats() {
        struct Node { let text: String?; let children: [Node] }
        let window = Node(text: nil, children: [
            Node(text: "Anna", children: []),
            Node(text: nil, children: [Node(text: " lunch? ", children: []), Node(text: "lunch?", children: []), Node(text: "", children: [])]),
            Node(text: "sure", children: [Node(text: "ignored child", children: [])]),
        ])
        #expect(FieldReader.visibleText(in: window, limit: 100, children: \.children, text: \.text) == "Anna\nlunch?\nsure")
        #expect(FieldReader.visibleText(in: window, limit: 6, children: \.children, text: \.text) == "Anna\nl")
    }

    @Test func privateBrowserWindowsAreNeverRead() {
        #expect(ScreenText.isPrivate(app: "org.mozilla.firefox", window: "Inbox — Private Browsing", toolbar: []))
        #expect(ScreenText.isPrivate(app: "com.google.Chrome", window: "New Tab", toolbar: ["Back", "Incognito"]))
        #expect(ScreenText.isPrivate(app: "com.microsoft.edgemac", window: "Bing", toolbar: ["InPrivate"]))
        #expect(ScreenText.isPrivate(app: "com.apple.Safari", window: "Apple", toolbar: ["Private"]))
        #expect(!ScreenText.isPrivate(app: "com.google.Chrome", window: "Private equity - Wikipedia", toolbar: ["Back", "Reload"]))
        #expect(!ScreenText.isPrivate(app: "com.tinyspeck.slackmacgap", window: "Private Browsing", toolbar: ["Private"]))
    }

    @Test func passwordManagersAreNeverRead() {
        #expect(ScreenText.excluded.contains("com.1password.1password"))
        #expect(ScreenText.excluded.contains("com.apple.loginwindow"))
    }
}
