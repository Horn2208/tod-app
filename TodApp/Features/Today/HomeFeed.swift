import Foundation

/// The order Home lays today's round out in, as one feed: your own song on
/// top, then everyone else's, the ones still waiting for your rating first.
/// Scrolling down the feed is how songs get rated -- there is no separate
/// rating screen to open from here.
enum HomeFeed {
    /// Today's songs in feed order: your own first, then those you have not
    /// rated, then those you have. Posting order within each part.
    ///
    /// `rated` is what was rated when the feed was laid out, not what is rated
    /// this second: a song that jumped to the end the moment it was rated
    /// would slide away under the thumb, before the gem or the reason.
    static func pages(running: [Submission], userID: String, rated: Set<Int>) -> [Submission] {
        let byTime = running.sorted { $0.postedAt < $1.postedAt }
        let own = byTime.filter { $0.posterID == userID }
        let others = byTime.filter { $0.posterID != userID }
        return own
            + others.filter { !rated.contains($0.id) }
            + others.filter { rated.contains($0.id) }
    }

    /// The first song in the feed still waiting for your rating -- where the
    /// hint under your song scrolls to. Nil when everything is rated.
    static func firstUnrated(in pages: [Submission], userID: String, rated: Set<Int>) -> Int? {
        pages.first { $0.posterID != userID && !rated.contains($0.id) }?.id
    }

    /// "2 Songs warten auf deine Bewertung". Nil when nothing waits, so the
    /// hint goes rather than saying "0".
    static func rateLine(toRate: Int) -> String? {
        switch toRate {
        case ..<1: nil
        case 1: "1 Song wartet auf deine Bewertung"
        default: "\(toRate) Songs warten auf deine Bewertung"
        }
    }
}
