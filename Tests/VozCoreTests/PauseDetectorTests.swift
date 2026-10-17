import Testing
@testable import VozCore

@Suite struct PauseDetectorTests {
    private let rate = Int(RecordingFilter.sampleRate)

    private func speech(_ seconds: Double, amplitude: Float = 0.3) -> [Float] {
        (0..<Int(seconds * Double(rate))).map { ($0 % 40 < 20 ? amplitude : -amplitude) }
    }

    private func silence(_ seconds: Double, level: Float = 0) -> [Float] {
        (0..<Int(seconds * Double(rate))).map { $0.isMultiple(of: 2) ? level : -level }
    }

    private func cuts(_ audio: [Float], chunk: Int = 1024) -> [Int] {
        var detector = PauseDetector()
        return stride(from: 0, to: audio.count, by: chunk).flatMap {
            detector.append(Array(audio[$0..<min($0 + chunk, audio.count)]))
        }
    }

    @Test func cutsAfterSixHundredMillisecondsOfSilence() {
        #expect(cuts(speech(3) + silence(1)) == [Int(3.6 * Double(rate))])
    }

    @Test func ignoresPausesShorterThanThreshold() {
        #expect(cuts(speech(3) + silence(0.4) + speech(3)).isEmpty)
    }

    @Test func keepsSegmentsShorterThanMinimum() {
        #expect(cuts(speech(1) + silence(0.8)).isEmpty)
    }

    @Test func doesNotCutLeadingSilence() {
        #expect(cuts(silence(3) + speech(1)).isEmpty)
    }

    @Test func resultIsIndependentOfChunkSize() {
        let audio = speech(3) + silence(1) + speech(3) + silence(1)
        #expect(cuts(audio, chunk: 1024) == cuts(audio, chunk: 333))
        #expect(cuts(audio).count == 2)
    }

    @Test func cutsRelativeToBackgroundNoise() {
        let noise = silence(0.7, level: 0.01)
        #expect(cuts(silence(1, level: 0.01) + speech(3) + noise).count == 1)
    }

    @Test func steadyNoiseWithoutSpeechNeverCuts() {
        #expect(cuts(silence(10, level: 0.01)).isEmpty)
    }

    @Test func shortensPauseAfterLongSegment() {
        #expect(cuts(speech(25) + silence(0.3)).count == 1)
        #expect(cuts(speech(10) + silence(0.3)).isEmpty)
    }
}
