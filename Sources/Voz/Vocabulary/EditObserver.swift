import AppKit
import ApplicationServices
import VozCore

@MainActor
final class EditObserver {
    static let readDelay = Duration.seconds(20)

    private struct Observation {
        let element: AXUIElement
        let inserted: String
        let timer: Task<Void, Never>
    }

    private let vocabulary: VocabularyStore
    private var pending: Observation?

    init(vocabulary: VocabularyStore) {
        self.vocabulary = vocabulary
    }

    func observe(inserted: String) {
        collect()
        guard AXIsProcessTrusted(), let element = Self.focusedElement() else { return }
        guard !Self.isSecure(element) else {
            Log.app.notice("Edit learning skipped, secure field")
            return
        }
        let timer = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.readDelay)
            } catch {
                return
            }
            self?.collect()
        }
        pending = Observation(element: element, inserted: inserted, timer: timer)
    }

    func collect() {
        guard let observation = pending else { return }
        pending = nil
        observation.timer.cancel()
        guard !Self.isSecure(observation.element), let current = Self.text(of: observation.element) else {
            Log.app.debug("Edit learning skipped, field unavailable")
            return
        }
        let words = EditLearner.suggestions(inserted: observation.inserted, current: current, isKnownWord: Self.isKnownWord)
        for word in words {
            do {
                try vocabulary.suggest(word)
                Log.app.notice("Vocabulary suggestion added from an edit")
            } catch {
                Log.app.error("Vocabulary suggestion failed: \(error.localizedDescription, privacy: .private)")
            }
        }
    }

    private static func focusedElement() -> AXUIElement? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, &value)
        guard status == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func isSecure(_ element: AXUIElement) -> Bool {
        let subrole = stringAttribute(kAXSubroleAttribute, of: element)
        let role = stringAttribute(kAXRoleAttribute, of: element)
        return subrole == kAXSecureTextFieldSubrole as String || role == "AXSecureTextField"
    }

    private static func text(of element: AXUIElement) -> String? {
        stringAttribute(kAXValueAttribute, of: element)
    }

    private static func stringAttribute(_ attribute: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func isKnownWord(_ word: String) -> Bool {
        let checker = NSSpellChecker.shared
        checker.automaticallyIdentifiesLanguages = true
        return checker.checkSpelling(of: word, startingAt: 0).location == NSNotFound
    }
}
