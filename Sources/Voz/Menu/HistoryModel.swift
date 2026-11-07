import Combine
import Foundation

@MainActor
final class HistoryModel: ObservableObject {
    @Published var query = ""
    @Published var day = HistoryModel.today
    @Published var showsCalendar = false
    @Published private(set) var records: [TranscriptRecord] = []
    /// Set together with `records`, so the list swaps in one step when you change days. `nil` while searching.
    @Published private(set) var listedDay: Date?
    @Published private(set) var days = TranscriptDays()

    private static var today: Date { Calendar.current.startOfDay(for: Date()) }

    private let store: HistoryStore
    private var subscription: AnyCancellable?
    private var daysSubscription: AnyCancellable?

    init(store: HistoryStore) {
        self.store = store
        subscription = $query
            .removeDuplicates()
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .combineLatest($day.removeDuplicates())
            .map { query, day in Self.observeList(query: query, day: day, store: store) }
            .switchToLatest()
            .sink(
                receiveCompletion: { completion in
                    if case let .failure(error) = completion {
                        Log.app.error("History observation failed: \(error.localizedDescription, privacy: .private)")
                    }
                },
                receiveValue: { [weak self] list in
                    self?.listedDay = list.day
                    self?.records = list.records
                }
            )
        daysSubscription = store.observeTranscriptDays()
            .sink(
                receiveCompletion: { completion in
                    if case let .failure(error) = completion {
                        Log.app.error("History days observation failed: \(error.localizedDescription, privacy: .private)")
                    }
                },
                receiveValue: { [weak self] in self?.update(days: $0) }
            )
    }

    /// Search looks through every day, so nothing you're looking for hides behind the day you're on
    private static func observeList(query: String, day: Date, store: HistoryStore) -> AnyPublisher<(day: Date?, records: [TranscriptRecord]), Error> {
        if !query.isEmpty {
            return store.observeSearch(query).map { (day: nil, records: $0) }.eraseToAnyPublisher()
        }
        guard let interval = Calendar.current.dateInterval(of: .day, for: day) else {
            return Empty().eraseToAnyPublisher()
        }
        return store.observeRecords(on: interval).map { (day: day, records: $0) }.eraseToAnyPublisher()
    }

    /// Deleting a past day's last transcript leaves nothing to show there, so the list goes back to today
    private func update(days: TranscriptDays) {
        self.days = days
        if day != Self.today, !days.contains(day) { day = Self.today }
    }

    var hasEarlierDay: Bool { days.earlier(than: day) != nil }
    var hasLaterDay: Bool { day < Self.today }

    func pick(_ picked: Date) {
        day = picked
        showsCalendar = false
    }

    /// Steps skip days without transcripts, so an arrow never lands on an empty page
    func showEarlierDay() -> Bool {
        guard let earlier = days.earlier(than: day) else { return false }
        pick(earlier)
        return true
    }

    func showLaterDay() -> Bool {
        guard hasLaterDay else { return false }
        pick(days.later(than: day) ?? Self.today)
        return true
    }

    /// Escape closes the calendar, then clears the search
    func dismissFilter() -> Bool {
        if showsCalendar {
            showsCalendar = false
        } else if !query.isEmpty {
            query = ""
        } else {
            return false
        }
        return true
    }

    /// The panel always opens on today, even if the app ran overnight
    func reset() {
        query = ""
        day = Self.today
        showsCalendar = false
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
