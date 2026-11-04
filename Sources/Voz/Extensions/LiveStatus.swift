import Observation
import Synchronization

/// What the running live transcription hears, so the notch and the note show that it still works
@MainActor
@Observable
final class LiveStatus {
    private(set) var running = false
    /// Everything transcribed so far, for copying
    private(set) var transcript = ""
    /// No audio arrives. Clears once the capture hears again.
    var stalled = false
    @ObservationIgnored let level = Level()

    /// The louder of the microphone and the call, written from the audio thread
    final class Level: Sendable {
        private let rms = Mutex((microphone: Float(0), call: Float(0)))

        func record(_ samples: [Float], fromCall: Bool = false) {
            let value = AudioLevel.rms(of: samples)
            rms.withLock { if fromCall { $0.call = value } else { $0.microphone = value } }
        }

        var normalized: Float { AudioLevel.normalized(rms: rms.withLock { max($0.microphone, $0.call) }) }
    }

    func begin() {
        running = true
        stalled = false
        transcript = ""
    }

    func end() {
        running = false
        stalled = false
        transcript = ""
        level.record([])
        level.record([], fromCall: true)
    }

    func hear(_ text: String) {
        transcript = text
    }
}
