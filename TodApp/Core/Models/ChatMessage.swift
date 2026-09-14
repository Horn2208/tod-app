import Foundation

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    var authorTag: String
    var authorName: String
    var text: String
    var isFromCurrentUser: Bool
    /// Ein heute geposteter Song, den diese Nachricht erwähnt.
    /// Zeigt eine kleine eingebettete Song-Karte statt reinem Text.
    var mentionedSubmissionID: Int? = nil
}
