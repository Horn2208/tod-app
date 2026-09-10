import Foundation
import Testing
@testable import TodApp

@Suite
struct RoundVisibilityTests {
    private let calendar = Calendar(identifier: .gregorian)
    /// Midday, not an arbitrary instant: the raw epoch value lands near 23:13
    /// local, where "yesterday plus an hour" tips over midnight into today and
    /// the test measures the timezone instead of the rule.
    private let today = Calendar(identifier: .gregorian)
        .startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        .addingTimeInterval(12 * 3600)

    private func daysAgo(_ n: Int) -> Date {
        calendar.date(byAdding: .day, value: -n, to: today)!
    }

    private func submission(_ id: Int, postedAt: Date) -> Submission {
        Submission(
            id: id, posterID: "mats", track: "Song \(id)", artist: "Wer auch immer",
            coverColorHex: "#000000", comments: [], postedAt: postedAt
        )
    }

    /// The core of the new rule: today shows nothing, however far along it is.
    @Test
    func todaysRoundIsNotRevealed() {
        #expect(RoundVisibility.isRevealed(roundDay: today, today: today, calendar: calendar) == false)
    }

    @Test
    func yesterdaysRoundIsRevealed() {
        #expect(RoundVisibility.isRevealed(roundDay: daysAgo(1), today: today, calendar: calendar))
    }

    @Test
    func anOlderRoundIsAlsoRevealed() {
        #expect(RoundVisibility.isRevealed(roundDay: daysAgo(9), today: today, calendar: calendar))
    }

    /// Late at night is still today. The rule is the calendar day, not a clock
    /// time, so nobody gets an early look by staying up.
    @Test
    func lateInTheEveningTodayIsStillNotRevealed() {
        let almostMidnight = calendar.startOfDay(for: today).addingTimeInterval(23 * 3600 + 59 * 60)

        #expect(
            RoundVisibility.isRevealed(
                roundDay: almostMidnight, today: almostMidnight, calendar: calendar
            ) == false
        )
    }

    @Test
    func theRevealedDayIsYesterday() {
        let day = RoundVisibility.revealedDay(today: today, calendar: calendar)

        #expect(calendar.isDate(day, inSameDayAs: daysAgo(1)))
    }

    @Test
    func onlyYesterdaysSongsAreOnShow() {
        let all = [
            submission(1, postedAt: today),
            submission(2, postedAt: daysAgo(1)),
            submission(3, postedAt: daysAgo(1).addingTimeInterval(3600)),
            submission(4, postedAt: daysAgo(5))
        ]

        let shown = RoundVisibility.revealedSubmissions(from: all, today: today, calendar: calendar)

        #expect(shown.map(\.id).sorted() == [2, 3])
    }

    @Test
    func aDayWithNoSongsShowsNothingRatherThanFallingBackFurther() {
        let all = [submission(1, postedAt: today), submission(2, postedAt: daysAgo(4))]

        let shown = RoundVisibility.revealedSubmissions(from: all, today: today, calendar: calendar)

        #expect(shown.isEmpty)
    }

    /// Ratings stay changeable all day, which is what the invisibility buys.
    @Test
    func todaysRoundIsStillVotable() {
        #expect(RoundVisibility.isVotable(roundDay: today, today: today, calendar: calendar))
    }

    /// Once everyone has seen the scores, changing a vote would rewrite history.
    @Test
    func aRevealedRoundIsNoLongerVotable() {
        #expect(
            RoundVisibility.isVotable(roundDay: daysAgo(1), today: today, calendar: calendar) == false
        )
    }
}
