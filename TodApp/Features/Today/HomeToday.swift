import Foundation

/// What Home has to decide before it can draw anything: whether you have
/// posted today, and which song that was. Kept out of the view so it can be
/// checked on its own, like Streak and GroupsFeed.
enum HomeToday {
    /// Your most recent song in this group. Nil when you have not posted --
    /// which is what puts Home into its other state.
    static func mySubmission(in group: Group, userID: String) -> Submission? {
        group.submissions
            .filter { $0.posterID == userID }
            .max { $0.postedAt < $1.postedAt }
    }

    static func me(in group: Group) -> Member? {
        group.members.first(where: \.isCurrentUser)
    }
}
