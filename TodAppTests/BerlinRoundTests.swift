import Foundation
import Testing
@testable import TodApp

/// Rounds follow Berlin's day, as the database does, wherever the phone is:
/// a phone in London counted 23:30 as "today" while the server had moved on
/// (the brief's second audit, A2).
@Suite
struct BerlinRoundTests {
    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    /// 00:30 in Berlin on 8 October is still 23:30 on 7 October in London.
    private var justAfterBerlinMidnight: Date { date("2026-10-07T22:30:00Z") }

    private func post(at iso: String) -> Submission {
        Submission(
            id: 1, posterID: "lena", track: "Nights", artist: "Frank Ocean",
            coverColorHex: "#222222", comments: [], postedAt: date(iso))
    }

    /// Posted at 23:00 Berlin on the 7th: by 00:30 Berlin it is yesterday's
    /// round, revealed -- not today's, as a London calendar would say.
    @Test
    func aPostFromBeforeBerlinMidnightIsYesterdaysRound() {
        let song = post(at: "2026-10-07T21:00:00Z")
        #expect(RoundVisibility.runningSubmissions(from: [song], today: justAfterBerlinMidnight).isEmpty)
        #expect(RoundVisibility.revealedSubmissions(from: [song], today: justAfterBerlinMidnight).map(\.id) == [1])
        #expect(!RoundVisibility.isVotable(roundDay: song.postedAt, today: justAfterBerlinMidnight))
    }

    /// The same moment on a London calendar, to show what the default fixes.
    @Test
    func aLondonCalendarWouldStillCallItToday() {
        var london = Calendar(identifier: .gregorian)
        london.timeZone = TimeZone(identifier: "Europe/London")!
        let song = post(at: "2026-10-07T21:00:00Z")
        #expect(RoundVisibility.isVotable(roundDay: song.postedAt, today: justAfterBerlinMidnight, calendar: london))
    }

    /// The day the reveal asks the server for is Berlin's yesterday.
    @Test
    func theRevealedDayIsBerlinsYesterday() {
        #expect(RoundDay.berlin(RoundVisibility.revealedDay(today: justAfterBerlinMidnight)) == "2026-10-07")
    }
}
