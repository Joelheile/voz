import Testing
import VozCore

@Suite struct RecentTimeTests {
    @Test func labelShortensWithAge() {
        #expect(RecentTime.label(for: listDate(secondsBeforeNow: -20), now: listNow, calendar: listCalendar) == "now")
        #expect(RecentTime.label(for: listDate(secondsBeforeNow: 30), now: listNow, calendar: listCalendar) == "now")
        #expect(RecentTime.label(for: listDate(secondsBeforeNow: 240), now: listNow, calendar: listCalendar) == "4m")
        #expect(RecentTime.label(for: listDate(day: 22, hour: 13), now: listNow, calendar: listCalendar) == "2h")
        #expect(RecentTime.label(for: listDate(day: 21, hour: 18, minute: 40), now: listNow, calendar: listCalendar) == "18:40")
        #expect(RecentTime.label(for: listDate(day: 20, hour: 9), now: listNow, calendar: listCalendar) == "Tue")
        #expect(RecentTime.label(for: listDate(day: 3, hour: 9), now: listNow, calendar: listCalendar) == "3 Oct")
        #expect(RecentTime.label(for: listDate(day: 3, hour: 9, year: 2025), now: listNow, calendar: listCalendar) == "3 Oct 2025")
    }

    @Test func headingGroupsTodayYesterdayAndEarlier() {
        #expect(RecentTime.heading(for: listDate(day: 22, hour: 1), now: listNow, calendar: listCalendar) == nil)
        #expect(RecentTime.heading(for: listDate(day: 21, hour: 23), now: listNow, calendar: listCalendar) == "Yesterday")
        #expect(RecentTime.heading(for: listDate(day: 20, hour: 12), now: listNow, calendar: listCalendar) == "Earlier")
    }
}

@Suite struct TranscriptSnippetTests {
    @Test func keepsTextWhenMatchIsNearTheStart() {
        let text = "Remind me to send the invoice before the end of the month."
        #expect(TranscriptSnippet.text(text, around: "send") == text)
    }

    @Test func startsNearALateMatchAtAWordBoundary() {
        let text = "Thanks for the quick turnaround yesterday, please attach the invoice PDF and cc finance."
        #expect(TranscriptSnippet.text(text, around: "INVOICE") == "… please attach the invoice PDF and cc finance.")
    }

    @Test func keepsTextWhenNothingMatches() {
        let text = "The build is green again after the dependency bump."
        #expect(TranscriptSnippet.text(text, around: "invoice") == text)
    }

    @Test func flattensLineBreaks() {
        #expect(TranscriptSnippet.text("First line\nsecond line", around: "") == "First line second line")
    }
}
