import Foundation

protocol VoteRepository: Sendable {
    func castVote(_ vote: Vote, groupID: String) async throws
    func setHiddenGem(submissionID: Int, voterID: String, groupID: String) async throws
    func submitVotes(voterID: String, groupID: String) async throws
}
