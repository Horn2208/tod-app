import Foundation

struct Submission: Identifiable, Codable {
    let id: Int
    var posterID: String
    var track: String
    var artist: String
    var coverColorHex: String
    var comments: [String]
    var source: TrackSource?
}
