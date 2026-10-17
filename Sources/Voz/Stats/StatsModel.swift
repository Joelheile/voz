import Combine
import Foundation
import VozCore

@MainActor
final class StatsModel: ObservableObject {
    @Published private(set) var stats = UsageStats()

    private var subscription: AnyCancellable?

    init(store: HistoryStore) {
        subscription = store.observeStats().receive(on: DispatchQueue.main).sink(
            receiveCompletion: { completion in
                if case let .failure(error) = completion {
                    Log.app.error("Stats observation failed: \(error.localizedDescription, privacy: .private)")
                }
            },
            receiveValue: { [weak self] in self?.stats = $0 }
        )
    }
}
