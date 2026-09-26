import Foundation

/// A song noted for later from the post sheet's search, without posting it
/// (the redesign brief, idea 3). It carries what a `TrackCandidate` carries,
/// so posting it later needs no second search, and when it was noted.
///
/// Kept on this phone only, per account (`SavedSongStorage`). Nobody else
/// sees it, so it has no table in the database.
struct SavedSong: Codable, Hashable, Identifiable, Sendable {
    /// The candidate's id: one entry per song, however often it is noted.
    var id: String
    var title: String
    var artist: String
    var source: TrackSource?
    var durationSeconds: Int?
    var isrc: String?
    var appleMusicID: String?
    var artworkURL: URL?
    var savedAt: Date

    init(_ candidate: TrackCandidate, savedAt: Date) {
        id = candidate.id
        title = candidate.title
        artist = candidate.artist
        source = candidate.source
        durationSeconds = candidate.durationSeconds
        isrc = candidate.isrc
        appleMusicID = candidate.appleMusicID
        artworkURL = candidate.artworkURL
        self.savedAt = savedAt
    }

    /// The song as a hit again, to be picked and posted like any other.
    var candidate: TrackCandidate {
        TrackCandidate(
            title: title, artist: artist, source: source,
            durationSeconds: durationSeconds, isrc: isrc,
            appleMusicID: appleMusicID, artworkURL: artworkURL)
    }
}

/// The list's rules, apart from any storage: newest first, each song once.
enum SavedSongs {
    /// Notes `song`. Noting a song again moves it to the top rather than
    /// listing it twice.
    static func adding(_ song: SavedSong, to list: [SavedSong]) -> [SavedSong] {
        [song] + list.filter { $0.id != song.id }
    }

    static func removing(id: String, from list: [SavedSong]) -> [SavedSong] {
        list.filter { $0.id != id }
    }
}
