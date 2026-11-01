import Testing
@testable import Voz

struct LiveChunkerTests {
    private let rate = Int(RecordingFilter.sampleRate)

    @Test func cutsAtTheQuietestMomentOnceTheLongestChunkFills() {
        var chunker = LiveChunker()
        var speech = [Float](repeating: 0.5, count: 14 * rate)
        let pause = 10 * rate
        speech.replaceSubrange(pause..<pause + rate / 10, with: repeatElement(0, count: rate / 10))
        #expect(chunker.append(Array(speech.prefix(13 * rate))).isEmpty)
        let chunks = chunker.append(Array(speech.dropFirst(13 * rate)))
        let cut = pause + rate / 20
        #expect(chunks.map(\.start) == [0])
        #expect(chunks.map(\.samples.count) == [cut])
        #expect(chunker.flush().map { ($0.start, $0.samples.count) } ?? (0, 0) == (Double(cut) / RecordingFilter.sampleRate, 14 * rate - cut))
        #expect(chunker.flush() == nil)
        #expect(chunker.seconds == 14)
    }
}

struct LiveTurnsTests {
    private func word(_ text: String, _ start: Double) -> TimedWord {
        TimedWord(text: text, start: start, end: start + 0.4)
    }

    @Test func holdsWordsUntilTheDiarizerReachesThemAndKeepsSpeakerNumbers() {
        var turns = LiveTurns()
        let spans = [SpeakerSpan(speaker: "A", start: 0, end: 2), SpeakerSpan(speaker: "B", start: 4.5, end: 6)]
        #expect(turns.take([word("Hi", 0), word("there.", 1), word("Hello.", 5)], spans: spans, diarizedUntil: 3) == [
            SpeakerTurn(speaker: 1, start: 0, end: 1.4, text: "Hi there."),
        ])
        #expect(turns.take([], spans: spans, diarizedUntil: 6) == [SpeakerTurn(speaker: 2, start: 5, end: 5.4, text: "Hello.")])
        let later = spans + [SpeakerSpan(speaker: "A", start: 6.5, end: 8)]
        #expect(turns.take([word("Bye.", 7)], spans: later, diarizedUntil: .infinity) == [SpeakerTurn(speaker: 1, start: 7, end: 7.4, text: "Bye.")])
    }
}

struct LiveMixTests {
    @Test func addsAlignedSamplesAndWaitsForTheOtherSource() {
        var mix = LiveMix()
        #expect(mix.add(mic: [1, 1]).isEmpty)
        #expect(mix.add(system: [2, 2, 2]) == [3, 3])
        #expect(mix.add(mic: [1]) == [3])
    }

    @Test func passesOneSourceThroughWhenTheOtherFallsSilent() {
        var mix = LiveMix()
        #expect(mix.add(mic: [Float](repeating: 1, count: LiveMix.maxLag)).isEmpty)
        #expect(mix.add(mic: [1]).count == LiveMix.maxLag + 1)
    }
}

struct LiveTranscriptTests {
    @Test func joinsPartsOfOneSpeakersTurn() {
        let transcript = LiveTranscript.make([
            SpeakerTurn(speaker: 1, start: 0, end: 1, text: "Hi"),
            SpeakerTurn(speaker: 1, start: 1.2, end: 2, text: "there."),
            SpeakerTurn(speaker: 2, start: 3, end: 4, text: "Hello."),
        ], seconds: 5)
        #expect(transcript == FileTranscript(text: "Hi there. Hello.", seconds: 5, speakers: 2, turns: [
            SpeakerTurn(speaker: 1, start: 0, end: 2, text: "Hi there."),
            SpeakerTurn(speaker: 2, start: 3, end: 4, text: "Hello."),
        ]))
    }
}
