import Foundation

struct Group: Identifiable, Codable {
    let id: String
    var name: String
    var icon: String
    /// A real picture for the group. `icon` stays as the fallback, so a group
    /// without one still shows something rather than a grey square. Defaulted
    /// to `nil` so every existing construction site -- none of which has a
    /// picture to supply -- keeps compiling.
    var imageData: Data? = nil
    var members: [Member]
    var roundEndsAt: Date
    var submissions: [Submission]
    var board: [BoardEntry]
    var chatMessages: [ChatMessage]
    var activeBattle: Battle?
}
