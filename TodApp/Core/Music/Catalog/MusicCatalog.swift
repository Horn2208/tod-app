import Foundation

/// One song as a music catalog knows it. Today that catalog is the iTunes
/// Store's, through the open Search API; with the paid developer account it
/// becomes Apple Music's through MusicKit. The ids are the same numbers --
/// an iTunes track id is what `music.apple.com/…?i=` carries.
struct CatalogSong: Equatable, Sendable {
    var id: String
    var title: String
    var artist: String
    /// Whole seconds of the full song, not of the preview.
    var durationSeconds: Int?
    /// Apple's fixed 30-second excerpt. Nil when the catalog offers none.
    var previewURL: URL?
    /// The song's page in Apple Music -- where "In Apple Music öffnen" goes.
    var pageURL: URL?
    /// The cover, for the mini player while the preview plays.
    var artworkURL: URL?
}

/// Where songs are looked up. A protocol so the MusicKit catalog can replace
/// the iTunes one without anything above it changing, and so tests can hand
/// in canned songs instead of a network.
protocol MusicCatalog: Sendable {
    /// Candidates for a title and artist, in the catalog's own order. Which
    /// of them -- if any -- is the song is `CatalogMatch`'s decision.
    func search(title: String, artist: String) async throws -> [CatalogSong]
    /// A song by the id stored with a post. Nil when the catalog no longer has it.
    func song(id: String) async throws -> CatalogSong?
}
