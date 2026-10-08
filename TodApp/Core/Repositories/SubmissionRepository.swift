import Foundation

protocol SubmissionRepository: Sendable {
    func submit(_ submission: Submission, to groupID: String) async throws
    func addComment(
        _ text: String,
        authorID: String,
        authorName: String,
        submissionID: Int,
        groupID: String
    ) async throws

    /// One's own post, while its round runs (`OwnContent.mayDelete`).
    func deleteSubmission(id: Int, groupID: String, asking userID: String) async throws
    /// One's own comment.
    func deleteComment(id: Int, submissionID: Int, groupID: String, asking userID: String) async throws
}

extension SubmissionRepository {
    func deleteSubmission(id: Int, groupID: String, asking userID: String) async throws {
        throw TodAppError.notAllowed
    }
    func deleteComment(id: Int, submissionID: Int, groupID: String, asking userID: String) async throws {
        throw TodAppError.notAllowed
    }
}
