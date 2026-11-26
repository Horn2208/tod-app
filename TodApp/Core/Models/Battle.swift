import Foundation

struct Battle: Codable {
    var mode: BattleMode
    var player1: BattleEntry
    var player2: BattleEntry
    var diceArtists: [String]
}

enum BattleMode: String, Codable {
    case free = "Frei"
    case artistDice = "Künstler-Würfel"
    case aux = "Aux Battle"
}

struct BattleEntry: Codable {
    var name: String
    var track: String
    var artist: String
    var coverColorHex: String
    var percentage: Int
    /// Same optional source as `Submission`: a battle entry is a track too, and
    /// without it the card had nothing but a colour to draw. Optional so battles
    /// stored before this existed still decode.
    var source: TrackSource?
}
