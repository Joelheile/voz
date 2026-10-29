import Testing
@testable import Voz

@Suite struct DebugLogTests {
    @Test func writesOneLinePerStepAndCopiesTheLatest() {
        let path = makeTemporaryStorePath() + ".jsonl"
        defer { removeFile(atPath: path) }
        let log = DebugLog(file: fileURL(path))
        log.write("dictation", ["outcome": "inserted", "ms": 120])
        log.write("extension", ["message": "voz-meeting: Recorder failed"])
        let latest = log.lastLines(1)
        #expect(latest.contains(#""step":"extension""#))
        #expect(latest.contains(#""message":"voz-meeting: Recorder failed""#))
        #expect(log.lastLines(200).split(separator: "\n").count == 2)
    }
}
