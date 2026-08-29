import Foundation

struct Vote: Codable {
    var voterID: String
    var submissionID: Int
    var rating: Rating
    var isHiddenGem: Bool
}

enum Rating: Int, Codable, CaseIterable {
    case awful = -2, meh = -1, ok = 0, good = 1, banger = 2

    var label: String {
        switch self {
        case .awful: "Aussetzer"
        case .meh: "Naja"
        case .ok: "Ok"
        case .good: "Gut"
        case .banger: "Banger"
        }
    }
}
