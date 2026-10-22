import Combine
import Foundation

@MainActor
final class StatsModel: ObservableObject {
    @Published private(set) var stats = UsageStats()

    private let store: HistoryStore
    private let now: @Sendable () -> Date
    private var subscription: AnyCancellable?

    init(store: HistoryStore, now: @escaping @Sendable () -> Date = Date.init) {
        self.store = store
        self.now = now
    }

    func start() {
        guard subscription == nil else { return }
        subscription = NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
            .merge(with: NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange))
            .map { _ in () }
            .prepend(())
            .setFailureType(to: Error.self)
            .map { [store, now] in store.observeStats(now: now) }
            .switchToLatest()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case let .failure(error) = completion {
                        Log.app.error("Stats observation failed: \(error.localizedDescription, privacy: .private)")
                    }
                },
                receiveValue: { [weak self] in self?.stats = $0 }
            )
    }

    func stop() {
        subscription = nil
    }
}
