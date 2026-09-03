import Foundation

/// What the current user has voted so far in one group's round. Loaded from the
/// repository rather than held in a view, so a half-finished round survives
/// leaving the tab.
struct MyVotes: Sendable, Equatable {
    var ratings: [Int: Rating] = [:]
    var hiddenGemID: Int?
    var hasSubmitted: Bool = false
}

/// One submission's result for the round. Computed in the repository so a later
/// backend can return the same number instead of every view recomputing it.
struct RoundScore: Identifiable, Sendable, Equatable {
    var id: Int { submissionID }
    var submissionID: Int
    /// Sum of every voter's rating, using the raw values -2 (Aussetzer) to +2 (Banger).
    var points: Int
    /// How many people marked this one as their hidden gem. Deliberately does
    /// not affect `points` -- awarding it a value would be a scoring rule, and
    /// those are not designed yet.
    var hiddenGemCount: Int
}

extension Array where Element == RoundScore {
    /// The submissions leading the round. Empty when nobody has voted; several
    /// entries on a tie, because a tie has no single winner to crown.
    var leaders: [RoundScore] {
        guard let best = map(\.points).max(), best > 0 else { return [] }
        return filter { $0.points == best }
    }
}
