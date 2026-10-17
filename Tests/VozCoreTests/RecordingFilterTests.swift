import Testing
@testable import VozCore

@Suite struct RecordingFilterTests {
    private func tone(seconds: Double, amplitude: Float) -> [Float] {
        let count = Int(seconds * RecordingFilter.sampleRate)
        return (0..<count).map { $0 % 2 == 0 ? amplitude : -amplitude }
    }

    @Test func shortRecordingIsDiscarded() {
        #expect(RecordingFilter.verdict(for: tone(seconds: 0.2, amplitude: 0.1)) == .tooShort)
    }

    @Test func silentRecordingIsDiscarded() {
        #expect(RecordingFilter.verdict(for: tone(seconds: 1, amplitude: 0.0005)) == .silent)
    }

    @Test func speechLevelRecordingIsKept() {
        #expect(RecordingFilter.verdict(for: tone(seconds: 1, amplitude: 0.05)) == .keep)
    }

    @Test func emptyRecordingIsTooShort() {
        #expect(RecordingFilter.verdict(for: []) == .tooShort)
    }

    @Test func exactMinimumDurationIsKept() {
        #expect(RecordingFilter.verdict(for: tone(seconds: 0.3, amplitude: 0.05)) == .keep)
    }
}
