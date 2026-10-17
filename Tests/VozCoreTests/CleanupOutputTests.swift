import Testing
@testable import VozCore

@Suite struct CleanupOutputTests {
    @Test func stripsTranscriptTags() {
        #expect(CleanupOutput.sanitized("<transcript>\nHello there.\n</transcript>", raw: "hello there") == "Hello there.")
    }

    @Test func stripsWrappingQuotesWhenInputHadNone() {
        #expect(CleanupOutput.sanitized("\"Hello there.\"", raw: "hello there") == "Hello there.")
    }

    @Test func keepsQuotesWhenInputHadThem() {
        #expect(CleanupOutput.sanitized("\"Hello there.\"", raw: "\"hello there\"") == "\"Hello there.\"")
    }
}
