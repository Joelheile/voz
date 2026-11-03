import Foundation
import Synchronization

/// Pings the main thread from a background thread, because code on a frozen main thread cannot report the freeze.
final class HangWatchdog: Sendable {
    private let seconds: TimeInterval
    private let onHang: @Sendable () -> Void
    private let generation = Atomic<Int>(0)

    init(seconds: TimeInterval, onHang: @escaping @Sendable () -> Void) {
        self.seconds = seconds
        self.onHang = onHang
    }

    func start() {
        let current = generation.add(1, ordering: .relaxed).newValue
        Thread.detachNewThread { [self] in watch(while: current) }
    }

    func stop() {
        generation.add(1, ordering: .relaxed)
    }

    private func watch(while current: Int) {
        while generation.load(ordering: .relaxed) == current {
            let answered = DispatchSemaphore(value: 0)
            DispatchQueue.main.async { answered.signal() }
            if answered.wait(timeout: .now() + seconds) == .timedOut {
                onHang()
                answered.wait()
            }
            Thread.sleep(forTimeInterval: seconds)
        }
    }
}

/// Names the slow system call the main thread is in, so a hang report says where it froze. Names are fixed, never user data.
enum MainThreadActivity {
    private static let current = Mutex<StaticString?>(nil)

    static var name: String? { current.withLock { $0.map { "\($0)" } } }

    @MainActor
    static func during<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T {
        let outer = current.withLock { current in
            defer { current = name }
            return current
        }
        defer { current.withLock { $0 = outer } }
        return try body()
    }
}
