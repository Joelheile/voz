import AppKit

/// The hostname of the web page that has focus, read through Accessibility. Extensions get only the hostname, never the path.
enum FocusedWebsite {
    static let browsers: Set<String> = chromium.union([
        "com.apple.Safari", "com.apple.SafariTechnologyPreview", "com.kagi.kagimacOS", "org.mozilla.firefox", "app.zen-browser.zen",
    ])
    private static let chromium: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary", "com.google.Chrome.dev", "org.chromium.Chromium",
        "company.thebrowser.Browser", "company.thebrowser.dia", "com.brave.Browser", "com.microsoft.edgemac",
        "com.vivaldi.Vivaldi", "com.operasoftware.Opera", "net.imput.helium",
    ]
    private static let messagingTimeout: Float = 0.25
    private static let budget = Duration.milliseconds(300)
    private static let maxDepth = 64

    /// Chromium builds its web accessibility tree only when an app asks for it, so Voz asks for every running browser
    /// when extensions load and again when one comes to the front.
    /// Chrome takes about 2 seconds to apply `AXEnhancedUserInterface` and reports kAXErrorNotImplemented even when it does.
    /// Browsers built on Electron read `AXManualAccessibility` instead.
    static func enableWebAccessibility(in app: NSRunningApplication?) {
        guard let app, let bundleID = app.bundleIdentifier, chromium.contains(bundleID), AXIsProcessTrusted() else { return }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        for attribute in ["AXEnhancedUserInterface", "AXManualAccessibility"] {
            AXUIElementSetAttributeValue(element, attribute as CFString, kCFBooleanTrue)
        }
    }

    static func hostname(pid: pid_t) -> String? {
        let deadline = ContinuousClock.now + budget
        guard let focused = focusedElement(pid: pid) else { return nil }
        return hostname(
            from: focused,
            parent: { ContinuousClock.now < deadline ? element(kAXParentAttribute, of: $0) : nil },
            webAreaURL: { attribute(kAXRoleAttribute, of: $0) as? String == "AXWebArea" ? attribute(kAXURLAttribute, of: $0) : nil }
        )
    }

    /// The outermost web page wins, so focus inside an iframe, such as the one Google Docs types into, still reports the page.
    static func hostname<Element>(from focused: Element, parent: (Element) -> Element?, webAreaURL: (Element) -> Any?) -> String? {
        var host: String?
        var element: Element? = focused
        for _ in 0..<maxDepth {
            guard let current = element else { break }
            host = hostname(from: webAreaURL(current)) ?? host
            element = parent(current)
        }
        return host
    }

    static func hostname(from url: Any?) -> String? {
        guard let url = (url as? URL) ?? (url as? String).flatMap(URL.init(string:)),
              ["http", "https"].contains(url.scheme?.lowercased()),
              let host = url.host()?.trimmingCharacters(in: ["."]), !host.isEmpty else { return nil }
        return host.lowercased()
    }

    // The system-wide element often fails with kAXErrorCannotComplete, so ask the app itself
    private static func focusedElement(pid: pid_t) -> AXUIElement? {
        element(kAXFocusedUIElementAttribute, of: AXUIElementCreateApplication(pid))
    }

    private static func element(_ name: String, of element: AXUIElement) -> AXUIElement? {
        guard let value = attribute(name, of: element), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}
