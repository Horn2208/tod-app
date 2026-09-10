import Foundation

/// What the current user has voted so far in one group's round. Loaded from the
/// repository rather than held in a view, so a half-finished round survives
/// leaving the tab.
///
/// There is no "submitted" flag: a round closes when its day ends, not when a
/// person declares themselves done. Until then every rating here may still be
/// changed, because nobody has seen any of them.
struct MyVotes: Sendable, Equatable {
    var ratings: [Int: Rating] = [:]
    /// The reason written beside a rating, by submission id. Separate from
    /// `ratings` rather than a pair, because a note without a rating is not a
    /// thing this app stores -- a note explains a rating.
    var notes: [Int: String] = [:]
    var hiddenGemID: Int?
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
