import Foundation

enum MusicService: String, Codable, Hashable {
    case spotify, soundcloud
}

/// Where a submitted track actually lives. Display truth stays on
/// `Submission.track` / `.artist`, so lists still render if a service is down.
struct TrackSource: Codable, Hashable {
    var service: MusicService
    var serviceTrackID: String
    var pageURL: URL
    var artworkURL: URL?
}

/// A search hit or a resolved link, before it becomes a Submission.
struct TrackCandidate: Identifiable, Hashable {
    var id: String {
        if let source { return "\(source.service.rawValue):\(source.serviceTrackID)" }
        return "apple:\(appleMusicID ?? "\(title)|\(artist)")"
    }
    var title: String
    var artist: String
    /// Nil for a hit from Apple's catalog, which has no Spotify or SoundCloud
    /// link: it posts as a song without one, played through Apple.
    var source: TrackSource?
    /// Whole seconds. Nil when the service did not say -- SoundCloud's oEmbed
    /// does not carry a length, and the picker then works from an assumption
    /// it admits to.
    var durationSeconds: Int?
    /// The recording's ISRC. Spotify's search carries it; a pasted link's
    /// oEmbed does not.
    var isrc: String?
    /// The Apple Music (iTunes) id, for a hit from Apple's catalog.
    var appleMusicID: String?
    /// The cover of a hit without a source; a linked one's is its source's.
    var artworkURL: URL?

    /// The cover to show beside the hit.
    var coverURL: URL? { source?.artworkURL ?? artworkURL }
}

extension TrackCandidate {
    init(appleSong song: CatalogSong) {
        self.init(
            title: song.title, artist: song.artist, source: nil,
            durationSeconds: song.durationSeconds, isrc: nil,
            // Apple's search answers with a 100-pixel cover; the post shows
            // it as large as the screen is wide.
            appleMusicID: song.id, artworkURL: ArtworkSize.large(song.artworkURL, side: 600))
    }
}
