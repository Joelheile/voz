import Testing
@testable import VozCore

struct WAVEncoderTests {
    @Test func writesA16BitMonoHeaderAndClampedSamples() {
        let bytes = [UInt8](WAVEncoder.encode([0, 1, -1, 2], sampleRate: 16_000))
        #expect(bytes.count == 44 + 8)
        #expect(String(decoding: bytes[0..<4], as: UTF8.self) == "RIFF")
        #expect(String(decoding: bytes[8..<16], as: UTF8.self) == "WAVEfmt ")
        #expect(Array(bytes[24..<28]) == [0x80, 0x3E, 0, 0])
        #expect(Array(bytes[40..<44]) == [8, 0, 0, 0])
        #expect(Array(bytes[44...]) == [0, 0, 0xFF, 0x7F, 0x01, 0x80, 0xFF, 0x7F])
    }
}
