import Foundation

/// The window in front, as an extension that reads the screen sees it: text through Accessibility, never pixels.
/// Voz keeps none of it. Extensions that ask for `"screen": true` in their package.json decide what to keep.
struct ScreenText: Encodable, Equatable, Sendable {
    static let maxText = 20_000
    /// Password managers and the lock screen are never read
    static let excluded: Set<String> = [
        "com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop", "com.lastpass.LastPass",
        "com.dashlane.dashlanephonefinal", "com.apple.keychainaccess", "com.apple.Passwords", "com.apple.loginwindow",
        "com.apple.ScreenSaver.Engine", "org.keepassxc.keepassxc",
    ]

    static let browsers: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview", "com.google.Chrome", "com.google.Chrome.beta",
        "com.google.Chrome.canary", "org.chromium.Chromium", "company.thebrowser.Browser", "com.brave.Browser",
        "com.microsoft.edgemac", "com.vivaldi.Vivaldi", "com.operasoftware.Opera", "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition", "app.zen-browser.zen",
    ]
    private static let privateLabels: Set<String> = ["private", "private browsing", "incognito", "inprivate"]

    /// Private browsing windows say so in their title (Firefox) or with a toolbar badge (Safari, Chrome, Arc, Brave, Edge)
    static func isPrivate(app: String, window: String, toolbar: [String]) -> Bool {
        guard browsers.contains(app) else { return false }
        let title = window.lowercased()
        return title.hasSuffix("private browsing") || title.hasSuffix("incognito") || title.hasSuffix("inprivate")
            || toolbar.contains { privateLabels.contains($0.trimmingCharacters(in: .whitespaces).lowercased()) }
    }

    let app: String
    let window: String
    /// The conversation the window shows, the same as `FocusedField.thread`
    let thread: UUID?
    /// With secrets hidden
    let text: String
}

/// Removes secrets before an extension sees the text: keys, tokens, private keys, card and bank numbers
enum Redaction {
    private static let patterns: [NSRegularExpression] = [
        #"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----"#,
        #"\b(sk|pk|rk)-[A-Za-z0-9_\-]{16,}"#,
        #"\b(ghp|gho|ghu|ghs|ghr|github_pat)_[A-Za-z0-9_]{20,}"#,
        #"\bxox[abposr]-[A-Za-z0-9\-]{10,}"#,
        #"\bAKIA[0-9A-Z]{16}\b"#,
        #"\bAIza[0-9A-Za-z_\-]{35}\b"#,
        #"\beyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}"#,
        #"(?i)\b(password|passwort|passcode|secret|token|api[_ -]?key)\b\s*[:=]\s*\S+"#,
        #"\b[A-Z]{2}\d{2}(?: ?[A-Z0-9]{4}){3,7}(?: ?[A-Z0-9]{1,4})?\b"#,
        #"\b(?:\d[ -]?){13,19}\b"#,
    ].map { try! NSRegularExpression(pattern: $0) }

    static func redact(_ text: String) -> String {
        patterns.reduce(text) { text, pattern in
            pattern.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "[hidden]")
        }
    }
}
