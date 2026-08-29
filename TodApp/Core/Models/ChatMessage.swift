import Foundation

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    var authorTag: String
    var authorName: String
    var text: String
    var isFromCurrentUser: Bool
}
