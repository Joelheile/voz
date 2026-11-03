import Testing
@testable import Voz

struct PauseDetectorTests {
    @Test func trailingSilenceCountsQuietSinceTheLastSpeech() {
        var detector = PauseDetector()
        _ = detector.append([Float](repeating: 0.1, count: 16_000))
        #expect(detector.trailingSilence == .zero)
        _ = detector.append([Float](repeating: 0, count: 3_200))
        #expect(detector.trailingSilence == .milliseconds(200))
        _ = detector.append([Float](repeating: 0.1, count: 320))
        #expect(detector.trailingSilence == .zero)
    }

    @Test func trailingSilenceSurvivesASegmentCut() {
        var detector = PauseDetector()
        _ = detector.append([Float](repeating: 0.1, count: 48_000))
        let cuts = detector.append([Float](repeating: 0, count: 16_000))
        #expect(cuts.count == 1)
        #expect(detector.trailingSilence == .seconds(1))
    }
}
