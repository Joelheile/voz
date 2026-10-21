import Synchronization

final class LiveLevel: Sendable {
    private let bits = Atomic<UInt32>(0)

    var rms: Float { Float(bitPattern: bits.load(ordering: .relaxed)) }

    func store(_ rms: Float) {
        bits.store(rms.bitPattern, ordering: .relaxed)
    }
}
