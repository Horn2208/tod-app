import Foundation

struct Group: Identifiable, Codable {
    let id: String
    var name: String
    var icon: String
    var members: [Member]
    var roundEndsAt: Date
    var submissions: [Submission]
    var board: [BoardEntry]
    var chatMessages: [ChatMessage]
    var activeBattle: Battle?
}
