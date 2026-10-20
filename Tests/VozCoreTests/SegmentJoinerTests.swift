import Testing
@testable import VozCore

@Suite struct SegmentJoinerTests {
    @Test func joinsWithSingleSpaces() {
        #expect(SegmentJoiner.join([" First one. ", "", "Second one.\n"], lowercaseContinuations: false) == "First one. Second one.")
    }

    @Test func keepsCapitalAfterSentenceEnd() {
        #expect(SegmentJoiner.join(["We left.", "Then it rained"], lowercaseContinuations: true) == "We left. Then it rained")
    }

    @Test func lowersCapitalAfterUnfinishedSentence() {
        #expect(SegmentJoiner.join(["We went to", "The store today."], lowercaseContinuations: true) == "We went to the store today.")
    }

    @Test func keepsCapitalWhenContinuationsDisabled() {
        #expect(SegmentJoiner.join(["Wir gehen in den", "Garten heute."], lowercaseContinuations: false) == "Wir gehen in den Garten heute.")
    }

    @Test func keepsPronounAcronymAndNames() {
        #expect(SegmentJoiner.join(["Yesterday", "I think"], lowercaseContinuations: true) == "Yesterday I think")
        #expect(SegmentJoiner.join(["Yesterday", "I'm sure"], lowercaseContinuations: true) == "Yesterday I'm sure")
        #expect(SegmentJoiner.join(["Send it to", "NASA now."], lowercaseContinuations: true) == "Send it to NASA now.")
        #expect(SegmentJoiner.join(["Send it to", "iPhone users"], lowercaseContinuations: true) == "Send it to iPhone users")
    }

    @Test func fallsBackPerSegment() {
        let text = SegmentJoiner.join(cleaned: ["Clean one.", nil, "Clean three."], fallback: ["raw one.", "rule two.", "raw three"], lowercaseContinuations: false)
        #expect(text == "Clean one. rule two. Clean three.")
    }

    @Test func dropsPeriodTheModelAddedAtAPause() {
        let text = SegmentJoiner.join(cleaned: ["Read how to build.", "Outreach and how to write it."], fallback: ["read how to build", "outreach and how to write it."], lowercaseContinuations: true)
        #expect(text == "Read how to build outreach and how to write it.")
    }

    @Test func keepsPeriodTheSpeakerEnded() {
        let text = SegmentJoiner.join(cleaned: ["We left.", "Then it rained."], fallback: ["we left.", "then it rained."], lowercaseContinuations: true)
        #expect(text == "We left. Then it rained.")
    }

    @Test func keepsPeriodOnTheLastSegment() {
        let text = SegmentJoiner.join(cleaned: ["We left."], fallback: ["we left"], lowercaseContinuations: true)
        #expect(text == "We left.")
    }
}
