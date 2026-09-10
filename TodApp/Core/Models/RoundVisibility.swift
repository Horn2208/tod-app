import Foundation

/// When a round's results may be seen.
///
/// The old rule tied it to the person: you saw the scores as soon as you had
/// submitted your own votes. The new one ties it to the calendar. A round is
/// revealed the day after its songs went up, and not before -- which is
/// exactly why ratings stay changeable while the day runs. Nothing is shown,
/// so nothing is spoiled by changing your mind.
enum RoundVisibility {
    /// A round is the set of songs posted on one day, identified by that day.
    static func isRevealed(
        roundDay: Date,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        calendar.startOfDay(for: roundDay) < calendar.startOfDay(for: today)
    }

    /// The day whose round is on show right now: yesterday. Today's songs are
    /// still being posted and rated.
    static func revealedDay(today: Date = Date(), calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: today))
            ?? calendar.startOfDay(for: today)
    }

    /// The submissions a reveal screen should show: those from the revealed
    /// day. A round still running shows nothing at all rather than a partial
    /// result -- the whole point of the rule.
    static func revealedSubmissions(
        from submissions: [Submission],
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> [Submission] {
        let day = revealedDay(today: today, calendar: calendar)
        return submissions.filter {
            calendar.isDate($0.postedAt, inSameDayAs: day)
        }
    }

    /// Whether a rating may still be changed: only while its round is running.
    /// Once a round is revealed, its votes are final because everyone has seen
    /// them.
    static func isVotable(
        roundDay: Date,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        calendar.isDate(roundDay, inSameDayAs: today)
    }
}
