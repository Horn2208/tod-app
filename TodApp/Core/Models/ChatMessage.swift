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
    /// Who wrote it, as the account id. Lets the chat tell one person's run
    /// of messages from the next (`ChatLayout`). Nil for the demo data.
    var authorID: String? = nil
    /// When it was sent. Nil for the demo data, which then shows no times.
    var sentAt: Date? = nil
}
