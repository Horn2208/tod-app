import Foundation

/// One reply under a posted song. Was a bare `String` until the comment screen
/// needed an author and a time to show next to the text.
struct Comment: Identifiable, Codable, Equatable {
    let id: Int
    var authorID: String
    var authorName: String
    var text: String
    var postedAt: Date
}
