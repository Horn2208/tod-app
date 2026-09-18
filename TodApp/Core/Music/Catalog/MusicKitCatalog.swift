import Foundation
import MusicKit

/// Apple Music's catalog through MusicKit -- what `ITunesCatalog` stood in for.
///
/// It knows what Apple Music streams rather than what the iTunes Store sells,
/// and it can look a recording up by ISRC. Every request needs two things this
/// code cannot supply itself: the MusicKit service switched on for the app's
/// bundle id in the developer account, and the listener's permission
/// (`MusicAuthorization`). Missing either, a request throws -- and the
/// resolver treats a throw as no answer, never as "not in the catalog".
struct MusicKitCatalog: MusicCatalog {
    func search(title: String, artist: String) async throws -> [CatalogSong] {
        var request = MusicCatalogSearchRequest(term: "\(title) \(artist)", types: [Song.self])
        // The same room as the iTunes search: album, single and deluxe
        // versions of one song would otherwise crowd out the right one.
        request.limit = 25
        return try await request.response().songs.map(Self.catalogSong(from:))
    }

    func song(id: String) async throws -> CatalogSong? {
        let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(id))
        return try await request.response().items.first.map(Self.catalogSong(from:))
    }

    func song(isrc: String) async throws -> CatalogSong? {
        let request = MusicCatalogResourceRequest<Song>(matching: \.isrc, equalTo: isrc)
        return try await request.response().items.first.map(Self.catalogSong(from:))
    }

    /// The ids are the numbers the iTunes catalog used, so a match stored with
    /// a post before MusicKit still looks up here.
    private static func catalogSong(from song: Song) -> CatalogSong {
        CatalogSong(
            id: song.id.rawValue,
            title: song.title,
            artist: song.artistName,
            durationSeconds: song.duration.map { Int($0.rounded()) },
            previewURL: song.previewAssets?.first?.url,
            pageURL: song.url,
            artworkURL: song.artwork?.url(width: 132, height: 132)
        )
    }
}

extension CatalogResolver {
    /// Offener iTunes-Katalog, kein Login nötig.
    static func appleMusicFirst() -> CatalogResolver {
        CatalogResolver(catalog: ITunesCatalog())
    }
}
