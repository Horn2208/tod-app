import Foundation

/// What Home has to decide before it can draw anything: whether you have
/// posted today, and which song that was. Kept out of the view so it can be
/// checked on its own, like Streak and GroupsFeed.
enum HomeToday {
    /// Your song in today's round. Nil when you have not posted today -- which
    /// is what puts Home into its other state.
    ///
    /// Yesterday's song is not a fallback. Taking merely the most recent one
    /// made Home show a song from a round that is over and closed, next to a
    /// streak that had already counted the day as missed.
    static func mySubmission(
        in group: Group,
        userID: String,
        today: Date = Date(),
        calendar: Calendar = RoundDay.berlinCalendar
    ) -> Submission? {
        RoundVisibility.runningSubmissions(from: group.submissions, today: today, calendar: calendar)
            .filter { $0.posterID == userID }
            .max { $0.postedAt < $1.postedAt }
    }

    static func me(in group: Group) -> Member? {
        group.members.first(where: \.isCurrentUser)
    }

    /// Where the group's round stands, for the card under one's own song
    /// (the brief's second audit, A4): who has posted, what is left to rate,
    /// when it is revealed.
    struct RoundStatus: Equatable {
        var posted: Int
        var members: Int
        /// Today's songs of others not rated yet.
        var toRate: Int
        /// Today's songs of others at all.
        var others: Int
        /// Until midnight in Berlin.
        var revealIn: TimeInterval
        /// Yesterday's songs, on show in the reveal.
        var revealed: Int
    }

    static func status(
        in group: Group,
        userID: String,
        rated: Set<Int>,
        now: Date = Date(),
        calendar: Calendar = RoundDay.berlinCalendar
    ) -> RoundStatus {
        let running = RoundVisibility.runningSubmissions(from: group.submissions, today: now, calendar: calendar)
        let others = running.filter { $0.posterID != userID }
        let turn = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return RoundStatus(
            posted: Set(running.map(\.posterID)).count,
            members: group.members.count,
            toRate: others.filter { !rated.contains($0.id) }.count,
            others: others.count,
            revealIn: max(0, turn.timeIntervalSince(now)),
            revealed: RoundVisibility.revealedSubmissions(from: group.submissions, today: now, calendar: calendar).count)
    }

    /// "3 von 5 haben gepostet · 2 Songs zu bewerten · Aufdeckung in 6 Std."
    static func line(_ status: RoundStatus) -> String {
        var parts = [status.posted == 1
            ? "1 von \(status.members) hat gepostet"
            : "\(status.posted) von \(status.members) haben gepostet"]
        if status.others > 0 {
            let ratingLine = switch status.toRate {
            case 0: "alles bewertet"
            case 1: "1 Song zu bewerten"
            default: "\(status.toRate) Songs zu bewerten"
            }
            parts.append(ratingLine)
        }
        parts.append("Aufdeckung in \(duration(status.revealIn))")
        return parts.joined(separator: " · ")
    }

    /// Hours, rounded up, or minutes in the last hour.
    static func duration(_ seconds: TimeInterval) -> String {
        if seconds < 3_600 {
            return "\(max(1, Int((seconds / 60).rounded(.up)))) Min."
        }
        return "\(Int((seconds / 3_600).rounded(.up))) Std."
    }
}
