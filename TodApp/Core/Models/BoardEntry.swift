import Foundation

struct BoardEntry: Identifiable, Codable {
    var id: String { name }
    var name: String
    var tag: String
    var points: Int
    var subtitle: String
}
