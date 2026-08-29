import Foundation

protocol SubmissionRepository: Sendable {
    func submit(_ submission: Submission, to groupID: String) async throws
    func addComment(_ text: String, submissionID: Int, groupID: String) async throws
}
