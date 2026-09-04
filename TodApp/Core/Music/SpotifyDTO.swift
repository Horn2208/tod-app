import Foundation

/// Mirrors just the slice of Spotify's search response we need. Note there is
/// deliberately no preview_url: Spotify stopped sending it to new apps in
/// November 2024, so previews come from the embed player instead.
enum SpotifyDTO {
    struct SearchResponse: Decodable {
        let tracks: TrackPage
    }
    struct TrackPage: Decodable {
        let items: [Track]
    }
    struct Track: Decodable {
        let id: String
        let name: String
        let artists: [Artist]
        let external_urls: ExternalURLs
        let album: Album
    }
    struct Artist: Decodable { let name: String }
    struct ExternalURLs: Decodable { let spotify: String }
    struct Album: Decodable { let images: [Image] }
    struct Image: Decodable { let url: String; let width: Int? }
}

enum SpotifyResponseMapper {
    /// Both the search row and the Reveal row draw a ~44pt tile, which a 3x
    /// phone renders at roughly this many pixels.
    private static let thumbnailPixels = 132

    /// The smallest image that still covers the tile. Spotify offers 640 / 300 /
    /// 64: hero art is a needless download, and the 64 arrives visibly upscaled.
    /// When nothing is big enough, the largest available still beats nothing.
    private static func thumbnail(from images: [SpotifyDTO.Image]) -> SpotifyDTO.Image? {
        let covering = images.filter { ($0.width ?? .max) >= thumbnailPixels }
        if let smallest = covering.min(by: { ($0.width ?? .max) < ($1.width ?? .max) }) {
            return smallest
        }
        return images.max(by: { ($0.width ?? 0) < ($1.width ?? 0) })
    }

    static func candidates(from data: Data) throws -> [TrackCandidate] {
        let response = try JSONDecoder().decode(SpotifyDTO.SearchResponse.self, from: data)
        return response.tracks.items.compactMap { track in
            guard let page = URL(string: track.external_urls.spotify) else { return nil }
            let artwork = thumbnail(from: track.album.images)
                .flatMap { URL(string: $0.url) }
            return TrackCandidate(
                title: track.name,
                artist: track.artists.map(\.name).joined(separator: ", "),
                source: TrackSource(
                    service: .spotify,
                    serviceTrackID: track.id,
                    pageURL: page,
                    artworkURL: artwork
                )
            )
        }
    }
}
