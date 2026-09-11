import Foundation

struct Member: Identifiable, Codable {
    let id: String
    var name: String
    var isCurrentUser: Bool

    /// The days this member posted on, newest last. Everything about whether
    /// someone has posted is derived from these rather than stored beside them,
    /// so nothing can drift out of sync with reality.
    var postedDates: [Date]

    var currentStreak: Int {
        Streak.current(from: postedDates)
    }

    /// Whether any of those posts fell on today's date.
    ///
    /// Computed, not stored. It used to be a flag set when someone posted and
    /// never cleared again, so across midnight a member kept the story ring for
    /// yesterday's song -- and the story row kept sorting them ahead of people
    /// who had actually posted today. `currentStreak` next to it was always
    /// derived for exactly this reason; this now follows the same rule.
    var hasPostedToday: Bool {
        Self.hasPosted(on: Date(), in: postedDates)
    }

    static func hasPosted(on day: Date, in dates: [Date], calendar: Calendar = .current) -> Bool {
        dates.contains { calendar.isDate($0, inSameDayAs: day) }
    }
}
