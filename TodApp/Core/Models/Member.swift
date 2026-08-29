import Foundation

struct Member: Identifiable, Codable {
    let id: String
    var name: String
    var isCurrentUser: Bool
    var hasPostedToday: Bool
}
