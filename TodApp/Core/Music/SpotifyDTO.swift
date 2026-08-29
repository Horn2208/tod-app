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
    static func candidates(from data: Data) throws -> [TrackCandidate] {
        let response = try JSONDecoder().decode(SpotifyDTO.SearchResponse.self, from: data)
        return response.tracks.items.compactMap { track in
            guard let page = URL(string: track.external_urls.spotify) else { return nil }
            // Smallest image: these are thumbnails in a list, not hero art.
            let artwork = track.album.images
                .min { ($0.width ?? .max) < ($1.width ?? .max) }
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
