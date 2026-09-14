import Foundation

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    var authorTag: String
    var authorName: String
    var text: String
    var isFromCurrentUser: Bool
    /// Today's (or any) song this message points at. Optional so older
    /// messages, and ones that are just talk, still decode.
    var mentionedSubmissionID: Int? = nil
}
