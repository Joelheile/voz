import AppKit
import ApplicationServices
import Combine

@MainActor
final class VocabularyModel: ObservableObject {
    @Published var draft = ""
    @Published private(set) var snapshot = VocabularySnapshot(words: [], suggestions: [])

    private let store: VocabularyStore
    private let analytics: Analytics
    private var subscription: AnyCancellable?

    init(store: VocabularyStore, analytics: Analytics) {
        self.store = store
        self.analytics = analytics
        subscription = store.observe().receive(on: DispatchQueue.main).sink(
            receiveCompletion: { completion in
                if case let .failure(error) = completion {
                    Log.app.error("Vocabulary observation failed: \(error.localizedDescription, privacy: .private)")
                }
            },
            receiveValue: { [weak self] in self?.snapshot = $0 }
        )
    }

    func addDraft() {
        perform("add") { try store.add(draft, source: .manual) }
        draft = ""
    }

    func remove(_ word: VocabularyWord) {
        perform("remove") { try store.remove(id: word.id) }
    }

    func accept(_ suggestion: VocabularySuggestion) {
        guard perform("accept", { try store.accept(suggestion) }) else { return }
        analytics.capture(.vocabularySuggestion(accepted: true))
    }

    func dismiss(_ suggestion: VocabularySuggestion) {
        guard perform("dismiss", { try store.dismiss(suggestion) }) else { return }
        analytics.capture(.vocabularySuggestion(accepted: false))
    }

    @discardableResult
    private func perform(_ action: String, _ work: () throws -> Void) -> Bool {
        do {
            try work()
            return true
        } catch {
            Log.app.error("Vocabulary \(action) failed: \(error.localizedDescription, privacy: .private)")
            return false
        }
    }
}

@MainActor
final class EditObserver {
    static let readDelay = Duration.seconds(20)
    private static let messagingTimeout: Float = 0.25

    private struct Observation {
        let element: AXUIElement
        let inserted: String
        let timer: Task<Void, Never>
    }

    private let learner: VocabularyLearner
    private var pending: Observation?

    init(learner: VocabularyLearner) {
        self.learner = learner
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
        let edits = EditLearner.edits(inserted: observation.inserted, current: current)
        let candidates = EditLearner.suggestions(inserted: observation.inserted, current: current, isKnownWord: Self.isKnownWord)
        guard !edits.isEmpty else { return }
        Task { [learner] in
            await learner.forget(edits)
            await learner.consider(candidates)
        }
    }

    private static func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, messagingTimeout)
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &value)
        guard status == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let element = value as! AXUIElement
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        return element
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

    static func isKnownWord(_ word: String) -> Bool {
        let checker = NSSpellChecker.shared
        checker.automaticallyIdentifiesLanguages = true
        return checker.checkSpelling(of: word, startingAt: 0).location == NSNotFound
    }
}
