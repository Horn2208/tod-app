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
    /// The recording's ISRC, when the service that found it said so --
    /// Spotify's search does. Kept for matching by ISRC once the Apple Music
    /// API is in reach; nothing reads it yet.
    var isrc: String?
    /// The Apple Music (iTunes) song this post was matched to. Nil when the
    /// catalog had no match, or was not asked.
    var appleMusicID: String?
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
        isrc: String? = nil,
        appleMusicID: String? = nil,
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
        self.isrc = isrc
        self.appleMusicID = appleMusicID
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
        isrc = try container.decodeIfPresent(String.self, forKey: .isrc)
        appleMusicID = try container.decodeIfPresent(String.self, forKey: .appleMusicID)
        postedAt = try container.decodeIfPresent(Date.self, forKey: .postedAt) ?? Date()
    }
}
