import Foundation

/// A round's result from its rows, the same arithmetic `InMemoryRepository`
/// does: the ratings summed per song, gems counted beside them without moving
/// the points, and every song in the round listed -- a song nobody rated
/// scored zero, which is not the same as not being there.
enum ScoreTally {
    static func scores(submissionIDs: [Int], votes: [VoteRecord], gems: [GemRecord]) -> [RoundScore] {
        let points = votes.reduce(into: [Int: Int]()) { $0[$1.submissionID, default: 0] += $1.rating }
        let gemCounts = gems.reduce(into: [Int: Int]()) { $0[$1.submissionID, default: 0] += 1 }
        return submissionIDs.map { id in
            RoundScore(submissionID: id, points: points[id] ?? 0, hiddenGemCount: gemCounts[id] ?? 0)
        }
    }
}

extension VoteRecord {
    /// The app's vote, or nil for a rating the app has no word for.
    var vote: Vote? {
        guard let rating = Rating(rawValue: rating) else { return nil }
        return Vote(
            voterID: voterID, submissionID: submissionID, rating: rating,
            isHiddenGem: false, note: note)
    }
}
