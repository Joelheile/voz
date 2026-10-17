import Foundation
import VozCore

final class LevelTap: @unchecked Sendable {
    private static let minimumDeliveryInterval = 1.0 / 60

    private let lock = NSLock()
    private let deliver: @Sendable (Float) -> Void
    private var smoother = LevelSmoother()
    private var lastProcessed: UInt64?
    private var lastDelivered: UInt64 = 0

    init(deliver: @escaping @Sendable (Float) -> Void) {
        self.deliver = deliver
    }

    func process(_ samples: [Float]) {
        let now = DispatchTime.now().uptimeNanoseconds
        let target = AudioLevel.normalized(rms: AudioLevel.rms(of: samples))
        let level: Float? = lock.withLock {
            let elapsed = lastProcessed.map { Double(now - $0) / 1e9 } ?? 0.02
            lastProcessed = now
            let smoothed = smoother.update(target: target, elapsedSeconds: elapsed)
            guard Double(now - lastDelivered) / 1e9 >= Self.minimumDeliveryInterval else { return nil }
            lastDelivered = now
            return smoothed
        }
        if let level { deliver(level) }
    }
}
