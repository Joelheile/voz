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

struct LiveEchoTests {
    private func words(_ text: String, from start: Double) -> [TimedWord] {
        text.split(separator: " ").enumerated().map { TimedWord(text: String($1), start: start + Double($0) * 0.4, end: start + Double($0) * 0.4 + 0.3) }
    }

    @Test func dropsWhatTheMicrophoneHeardFromTheSpeakers() {
        let played = words("Did you finish the quarterly report", from: 10)
        let heard = words("did you finish the quarterly report", from: 10.2)
        #expect(LiveEcho.remove(heard, played: played).isEmpty)
    }

    @Test func keepsTheUsersOwnWordsAndShortOverlaps() {
        let played = words("so the report is late", from: 10)
        let heard = words("yes so I will send it", from: 10.1)
        #expect(LiveEcho.remove(heard, played: played).map(\.text) == ["yes", "so", "I", "will", "send", "it"])
    }

    @Test func keepsWordsThatMatchOnlyLongBefore() {
        let played = words("quarterly report", from: 0)
        let heard = words("quarterly report", from: 30)
        #expect(LiveEcho.remove(heard, played: played).count == 2)
    }

    @Test func waitsForTheSystemAudioThenFilters() async {
        let echo = LiveEcho()
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            await echo.heard(words("quarterly report numbers", from: 1), until: 5)
        }
        let kept = await echo.removeEcho(from: words("quarterly report numbers", from: 1.1))
        #expect(kept.isEmpty)
    }
}

struct LiveTranscriptCombineTests {
    @Test func putsTheUsersTurnsAndTheCallInTimeOrder() {
        let you = FileTranscript(text: "Almost.", seconds: 8, speakers: 1, turns: [SpeakerTurn(speaker: 0, start: 4, end: 5, text: "Almost.", you: true)])
        let call = FileTranscript(text: "Done? Great.", seconds: 9, speakers: 1, turns: [
            SpeakerTurn(speaker: 1, start: 0, end: 2, text: "Done?"),
            SpeakerTurn(speaker: 1, start: 6, end: 7, text: "Great."),
        ])
        let combined = LiveTranscript.combine(you: you, call: call)
        #expect(combined.turns.map(\.text) == ["Done?", "Almost.", "Great."])
        #expect(combined.turns.map(\.you) == [nil, true, nil])
        #expect(combined.speakers == 2)
        #expect(combined.seconds == 9)
    }
}
