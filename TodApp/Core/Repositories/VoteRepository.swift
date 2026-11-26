import Foundation

protocol VoteRepository: Sendable {
    func castVote(_ vote: Vote, groupID: String) async throws
    func setHiddenGem(submissionID: Int, voterID: String, groupID: String) async throws

    /// The current user's own votes in one day's round, so the UI can show what
    /// was already cast instead of starting blank on every launch. Scoped to a
    /// day because a round is a day -- yesterday's gem has to stay where it was
    /// set once its scores are out.
    func fetchMyVotes(voterID: String, groupID: String, day: Date) async throws -> MyVotes

    /// Every submission's result for one day's round, including ones nobody
    /// rated. The caller names the day; whether that day may be shown at all is
    /// `RoundVisibility`'s decision, not the repository's.
    func fetchRoundScores(groupID: String, day: Date) async throws -> [RoundScore]

    /// Every vote cast in one day's round. A reveal shows who said what, and
    /// a score alone cannot carry a note.
    func fetchVotes(groupID: String, day: Date) async throws -> [Vote]

    /// Every revealed round's scores in one group, for the season table.
    /// Today's round is left out on purpose: it is not decided, and a season
    /// total that moved as votes came in would be a running score of a secret.
    func fetchRevealedScores(groupID: String) async throws -> [RoundScore]
}
