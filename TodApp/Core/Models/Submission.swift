import Foundation

struct Submission: Identifiable, Codable {
    let id: Int
    var posterID: String
    var track: String
    var artist: String
    var coverColorHex: String
    var comments: [String]
    var source: TrackSource?
    /// The stretch the poster picked out. Optional so posts made before the
    /// picker existed still decode.
    var section: TrackSection?
}
