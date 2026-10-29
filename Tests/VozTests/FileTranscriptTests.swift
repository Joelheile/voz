import Testing
@testable import Voz

struct SpeakerTurnsTests {
    private func word(_ text: String, _ start: Double) -> TimedWord {
        TimedWord(text: text, start: start, end: start + 0.4)
    }

    @Test func groupsWordsIntoTurnsNumberedInSpeakingOrder() {
        let words = [word("Hi", 0), word("there.", 0.5), word("Hello!", 2), word("How", 3), word("are", 3.5), word("you?", 4)]
        let spans = [
            SpeakerSpan(speaker: "S7", start: 0, end: 1.2),
            SpeakerSpan(speaker: "S2", start: 1.8, end: 2.6),
            SpeakerSpan(speaker: "S7", start: 2.9, end: 4.5),
        ]
        #expect(SpeakerTurns.make(words: words, spans: spans) == [
            SpeakerTurn(speaker: 1, start: 0, end: 0.9, text: "Hi there."),
            SpeakerTurn(speaker: 2, start: 2, end: 2.4, text: "Hello!"),
            SpeakerTurn(speaker: 1, start: 3, end: 4.4, text: "How are you?"),
        ])
    }

    @Test func givesWordsOutsideEverySpanToTheNearestSpeaker() {
        let words = [word("one", 0), word("two", 2), word("three", 9.5)]
        let spans = [SpeakerSpan(speaker: "A", start: 0, end: 1), SpeakerSpan(speaker: "B", start: 8, end: 9)]
        #expect(SpeakerTurns.make(words: words, spans: spans).map(\.text) == ["one two", "three"])
    }

    @Test func keepsEverythingInOneTurnWithoutSpans() {
        let words = [word("just", 1), word("me", 2)]
        #expect(SpeakerTurns.make(words: words, spans: []) == [SpeakerTurn(speaker: 1, start: 1, end: 2.4, text: "just me")])
        #expect(SpeakerTurns.make(words: [], spans: []).isEmpty)
    }
}

struct MediaFileTests {
    @Test func acceptsAudioAndVideoThatCoreAudioReads() {
        for path in ["/a/call.mp3", "/a/memo.m4a", "/a/talk.wav", "/a/song.aiff", "/a/take.flac", "/a/meeting.mp4", "/a/screen.mov", "/a/clip.m4v"] {
            #expect(MediaFile.isSupported(fileURL(path)), "\(path)")
        }
    }

    @Test func rejectsOtherFiles() {
        for path in ["/a/movie.mkv", "/a/notes.txt", "/a/photo.png", "/a/no-extension", "/a/subs.vtt", "/a/list.m3u", "/a/captions.scc"] {
            #expect(!MediaFile.isSupported(fileURL(path)), "\(path)")
        }
    }

    @Test func tellsTransportStreamVideoFromTypeScriptSource() throws {
        let directory = temporaryHome().root
        try writeFile("G\u{40}\u{00}\u{10}", named: "clip.ts", in: directory)
        try writeFile("export const voz = 1\n", named: "voz.ts", in: directory)
        #expect(MediaFile.isSupported(directory.appendingPathComponent("clip.ts")))
        #expect(!MediaFile.isSupported(directory.appendingPathComponent("voz.ts")))
    }

    @Test func tellsAVCHDVideoFromTypeScriptModule() throws {
        let directory = temporaryHome().root
        try writeFile("\u{00}\u{00}\u{00}\u{00}G\u{40}\u{00}\u{10}", named: "clip.mts", in: directory)
        try writeFile("export const voz = 1\n", named: "voz.mts", in: directory)
        #expect(MediaFile.isSupported(directory.appendingPathComponent("clip.mts")))
        #expect(!MediaFile.isSupported(directory.appendingPathComponent("voz.mts")))
    }
}
