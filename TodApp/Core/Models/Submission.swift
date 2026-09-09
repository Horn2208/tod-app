import Foundation

struct Submission: Identifiable, Codable {
    let id: Int
    var posterID: String
    var track: String
    var artist: String
    var coverColorHex: String
    var comments: [Comment]
    var source: TrackSource?
    /// The stretch the poster picked out. Optional so posts made before the
    /// picker existed still decode.
    var section: TrackSection?
    /// When this song went up. The groups feed shows it beside each row, and
    /// orders rows by it -- the group's `roundEndsAt` is the round's deadline,
    /// not a post's time, and using it there would put a plausible-looking
    /// wrong number on every row.
    var postedAt: Date

    init(
        id: Int,
        posterID: String,
        track: String,
        artist: String,
        coverColorHex: String,
        comments: [Comment],
        source: TrackSource? = nil,
        section: TrackSection? = nil,
        postedAt: Date = Date()
    ) {
        self.id = id
        self.posterID = posterID
        self.track = track
        self.artist = artist
        self.coverColorHex = coverColorHex
        self.comments = comments
        self.source = source
        self.section = section
        self.postedAt = postedAt
    }

    /// Written out rather than synthesised so a payload without `postedAt`
    /// still decodes: the synthesised version demands every non-optional key,
    /// and a stored post from before this field existed has none.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        posterID = try container.decode(String.self, forKey: .posterID)
        track = try container.decode(String.self, forKey: .track)
        artist = try container.decode(String.self, forKey: .artist)
        coverColorHex = try container.decode(String.self, forKey: .coverColorHex)
        comments = try container.decodeIfPresent([Comment].self, forKey: .comments) ?? []
        source = try container.decodeIfPresent(TrackSource.self, forKey: .source)
        section = try container.decodeIfPresent(TrackSection.self, forKey: .section)
        postedAt = try container.decodeIfPresent(Date.self, forKey: .postedAt) ?? Date()
    }
}
