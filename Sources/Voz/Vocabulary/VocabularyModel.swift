import Combine
import Foundation
import VozCore

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
