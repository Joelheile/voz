import AppKit

/// The text field that has focus, read through Accessibility, so an extension can rewrite what you are typing.
/// `before` and `after` hold the text on screen around the field, nearest text last and first.
struct FocusedField: Encodable, Equatable, Sendable {
    let text: String
    let selection: TextRange
    let role: String
    let label: String?
    let window: String?
    let before: String
    let after: String
    /// The conversation the window shows, so an extension can read what you wrote there before
    var thread: FieldThread? = nil
}

struct FieldThread: Encodable, Equatable, Sendable {
    let id: UUID
    let title: String
}

/// Offsets count UTF-16 code units, like JavaScript string indexes.
struct TextRange: Codable, Equatable, Sendable {
    let start: Int
    let length: Int
}

enum FieldReader {
    static let beforeLimit = 6000
    static let afterLimit = 1500
    private static let messagingTimeout: Float = 0.25
    private static let budget = Duration.milliseconds(500)
    private static let maxNodes = 3000
    private static let maxDepth = 32

    static func read(pid: pid_t) -> FocusedField? {
        let deadline = ContinuousClock.now + budget
        guard AXIsProcessTrusted(), let field = focusedTextElement(pid: pid),
              let text = attribute(kAXValueAttribute, of: field) as? String,
              let selection = selectedRange(of: field) else { return nil }
        let inTime = { ContinuousClock.now < deadline }
        let around = surroundingText(
            of: field,
            parent: { inTime() ? element(kAXParentAttribute, of: $0) : nil },
            children: { inTime() ? elements(kAXChildrenAttribute, of: $0) : [] },
            text: { attribute(kAXValueAttribute, of: $0) as? String }
        )
        let label = [kAXDescriptionAttribute, kAXTitleAttribute, kAXPlaceholderValueAttribute]
            .lazy.compactMap { attribute($0, of: field) as? String }.first { !$0.isEmpty }
        return FocusedField(
            text: text,
            selection: selection,
            role: attribute(kAXRoleAttribute, of: field) as? String ?? "",
            label: label,
            window: windowTitle(of: field),
            before: around.before,
            after: around.after
        )
    }

    /// Some apps accept the new selection but ignore it, so this reads it back.
    static func select(_ range: TextRange, pid: pid_t) -> Bool {
        guard AXIsProcessTrusted(), range.start >= 0, range.length >= 0, let field = focusedTextElement(pid: pid) else { return false }
        var cfRange = CFRange(location: range.start, length: range.length)
        guard let value = AXValueCreate(.cfRange, &cfRange),
              AXUIElementSetAttributeValue(field, kAXSelectedTextRangeAttribute as CFString, value) == .success else { return false }
        return selectedRange(of: field) == range
    }

    /// Walks out from the field and reads the text of its siblings at each level, nearest first, until both sides are full.
    /// An element with text of its own counts once, so a text area's static text children don't repeat it.
    static func surroundingText<Element: Equatable>(
        of field: Element,
        limits: (before: Int, after: Int) = (beforeLimit, afterLimit),
        parent: (Element) -> Element?,
        children: (Element) -> [Element],
        text: (Element) -> String?
    ) -> (before: String, after: String) {
        var nodesLeft = maxNodes
        func subtreeText(_ root: Element, depth: Int = 0) -> [String] {
            guard nodesLeft > 0, depth < maxDepth else { return [] }
            nodesLeft -= 1
            if let own = text(root)?.trimmingCharacters(in: .whitespacesAndNewlines), !own.isEmpty { return [own] }
            return children(root).flatMap { subtreeText($0, depth: depth + 1) }
        }

        var before: [String] = [], after: [String] = []
        var beforeCount = 0, afterCount = 0
        var child = field
        var level = parent(field)
        for _ in 0..<maxDepth {
            guard let current = level, nodesLeft > 0, beforeCount < limits.before || afterCount < limits.after else { break }
            let siblings = children(current)
            if let index = siblings.firstIndex(of: child) {
                for sibling in siblings[..<index].reversed() where beforeCount < limits.before {
                    let chunk = subtreeText(sibling).joined(separator: "\n")
                    guard !chunk.isEmpty else { continue }
                    before.append(chunk)
                    beforeCount += chunk.utf16.count
                }
                for sibling in siblings[(index + 1)...] where afterCount < limits.after {
                    let chunk = subtreeText(sibling).joined(separator: "\n")
                    guard !chunk.isEmpty else { continue }
                    after.append(chunk)
                    afterCount += chunk.utf16.count
                }
            }
            child = current
            level = parent(current)
        }
        return (
            String(before.reversed().joined(separator: "\n").suffix(limits.before)),
            String(after.joined(separator: "\n").prefix(limits.after))
        )
    }

    /// What a draft replaced, and where: cheaper than `read`, because it skips the text around the field
    static func selection(pid: pid_t) -> (text: String, window: String?)? {
        guard AXIsProcessTrusted(), let field = focusedTextElement(pid: pid) else { return nil }
        return (attribute(kAXSelectedTextAttribute, of: field) as? String ?? "", windowTitle(of: field))
    }

    /// The text a window shows, top to bottom, for `voz.screen()`. Skips password fields.
    /// `toolbar` holds the toolbar's labels, where browsers mark private windows.
    static func windowText(pid: pid_t, limit: Int) -> (window: String, toolbar: [String], text: String)? {
        let deadline = ContinuousClock.now + budget
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        guard AXIsProcessTrusted(), let window = element(kAXFocusedWindowAttribute, of: app),
              let title = attribute(kAXTitleAttribute, of: window) as? String else { return nil }
        let text = visibleText(
            in: window,
            limit: limit,
            children: { ContinuousClock.now < deadline ? elements(kAXChildrenAttribute, of: $0) : [] },
            text: { element in
                let role = attribute(kAXRoleAttribute, of: element) as? String
                guard role != "AXSecureTextField", attribute(kAXSubroleAttribute, of: element) as? String != kAXSecureTextFieldSubrole,
                      [kAXStaticTextRole, kAXTextAreaRole, kAXTextFieldRole].contains(role) else { return nil }
                return attribute(kAXValueAttribute, of: element) as? String
            }
        )
        return (title, toolbarLabels(of: window), text)
    }

    /// What says a window is private, without reading its text
    static func windowLabels(pid: pid_t) -> (title: String, toolbar: [String])? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        guard AXIsProcessTrusted(), let window = element(kAXFocusedWindowAttribute, of: app),
              let title = attribute(kAXTitleAttribute, of: window) as? String else { return nil }
        return (title, toolbarLabels(of: window))
    }

    private static func toolbarLabels(of window: AXUIElement) -> [String] {
        func labels(_ element: AXUIElement, depth: Int) -> [String] {
            let own = [kAXTitleAttribute, kAXDescriptionAttribute].compactMap { attribute($0, of: element) as? String }
            guard depth < 3 else { return own }
            return own + elements(kAXChildrenAttribute, of: element).flatMap { labels($0, depth: depth + 1) }
        }
        return elements(kAXChildrenAttribute, of: window)
            .filter { attribute(kAXRoleAttribute, of: $0) as? String == kAXToolbarRole }
            .flatMap { labels($0, depth: 0) }
    }

    static func visibleText<Element>(in root: Element, limit: Int, children: (Element) -> [Element], text: (Element) -> String?) -> String {
        var lines: [String] = []
        var count = 0
        var nodesLeft = maxNodes
        func visit(_ element: Element, depth: Int) {
            guard nodesLeft > 0, depth < maxDepth, count < limit else { return }
            nodesLeft -= 1
            if let own = text(element)?.trimmingCharacters(in: .whitespacesAndNewlines), !own.isEmpty {
                if lines.last != own {
                    lines.append(own)
                    count += own.count + 1
                }
                return
            }
            children(element).forEach { visit($0, depth: depth + 1) }
        }
        visit(root, depth: 0)
        return String(lines.joined(separator: "\n").prefix(limit))
    }

    static func windowTitle(pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        return element(kAXFocusedWindowAttribute, of: app).flatMap { attribute(kAXTitleAttribute, of: $0) as? String }
    }

    static func windowTitle(of field: AXUIElement) -> String? {
        element(kAXWindowAttribute, of: field).flatMap { attribute(kAXTitleAttribute, of: $0) as? String }
    }

    static func text(of field: AXUIElement) -> String? {
        attribute(kAXValueAttribute, of: field) as? String
    }

    /// Electron apps such as Slack build their accessibility tree only once an app asks, so the first read there can come back empty.
    static func focusedTextElement(pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        guard let focused = element(kAXFocusedUIElementAttribute, of: app) else { return nil }
        let isSecure = attribute(kAXRoleAttribute, of: focused) as? String == "AXSecureTextField"
            || attribute(kAXSubroleAttribute, of: focused) as? String == kAXSecureTextFieldSubrole
        return isSecure ? nil : focused
    }

    private static func selectedRange(of element: AXUIElement) -> TextRange? {
        guard let value = attribute(kAXSelectedTextRangeAttribute, of: element), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return TextRange(start: range.location, length: range.length)
    }

    private static func element(_ name: String, of element: AXUIElement) -> AXUIElement? {
        guard let value = attribute(name, of: element), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func elements(_ name: String, of element: AXUIElement) -> [AXUIElement] {
        attribute(name, of: element) as? [AXUIElement] ?? []
    }

    private static func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}
