import Foundation

struct Vote: Codable {
    var voterID: String
    var submissionID: Int
    var rating: Rating
    var isHiddenGem: Bool
    /// Why this rating, in the voter's own words. Read only once the round is
    /// revealed -- like the rating itself, it is nobody's business while the
    /// day runs. Optional, so votes cast before notes existed still decode.
    var note: String? = nil
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
