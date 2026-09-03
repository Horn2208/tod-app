import Foundation

protocol VoteRepository: Sendable {
    func castVote(_ vote: Vote, groupID: String) async throws
    func setHiddenGem(submissionID: Int, voterID: String, groupID: String) async throws
    func submitVotes(voterID: String, groupID: String) async throws

    /// The current user's own votes, so the UI can show what was already cast
    /// instead of starting blank on every launch.
    func fetchMyVotes(voterID: String, groupID: String) async throws -> MyVotes

    /// Every submission's result for the round, including ones nobody rated.
    func fetchRoundScores(groupID: String) async throws -> [RoundScore]
}
