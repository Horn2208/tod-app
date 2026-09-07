import Foundation

struct Member: Identifiable, Codable {
    let id: String
    var name: String
    var isCurrentUser: Bool
    var hasPostedToday: Bool

    /// The days this member posted on, newest last. The streak is derived from
    /// these rather than stored, so it cannot drift out of sync with reality.
    var postedDates: [Date]

    var currentStreak: Int {
        Streak.current(from: postedDates)
    }
}
