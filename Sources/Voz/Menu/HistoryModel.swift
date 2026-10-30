import Combine
import Foundation

@MainActor
final class HistoryModel: ObservableObject {
    @Published var query = ""
    @Published private(set) var records: [TranscriptRecord] = []

    private let store: HistoryStore
    private var subscription: AnyCancellable?

    init(store: HistoryStore) {
        self.store = store
        subscription = $query
            .removeDuplicates()
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .map { store.observeSearch($0) }
            .switchToLatest()
            .sink(
                receiveCompletion: { completion in
                    if case let .failure(error) = completion {
                        Log.app.error("History observation failed: \(error.localizedDescription, privacy: .private)")
                    }
                },
                receiveValue: { [weak self] in self?.records = $0 }
            )
    }

    func usage() async -> UsageStats? {
        do {
            return try await Task.detached { [store] in try store.stats() }.value
        } catch {
            Log.app.error("History stats failed: \(error.localizedDescription, privacy: .private)")
            return nil
        }
    }

    func delete(_ record: TranscriptRecord) {
        do {
            try store.delete(id: record.id)
        } catch {
            Log.app.error("History delete failed: \(error.localizedDescription, privacy: .private)")
        }
    }
}
