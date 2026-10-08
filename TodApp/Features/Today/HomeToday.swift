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
}
