import Foundation

/// Spotify's oEmbed endpoint is public and needs no client credentials or
/// access token -- unlike search, which goes through SpotifySearchRepository
/// and the token provider. Used only to resolve display metadata for a
/// pasted link, never to search.
enum SpotifyOEmbedMapper {
    struct Response: Decodable {
        let title: String
        let thumbnail_url: String?
    }

    static func candidate(from data: Data, source: TrackSource) throws -> TrackCandidate {
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        var resolved = source
        resolved.artworkURL = decoded.thumbnail_url.flatMap { URL(string: $0) }
        // Spotify's oEmbed response has no author_name field, unlike
        // SoundCloud's. Put the whole title in `title` and leave `artist`
        // empty rather than guessing a split out of the title string.
        return TrackCandidate(title: decoded.title, artist: "", source: resolved)
    }
}

struct SpotifyOEmbedClient: Sendable {
    typealias PerformRequest = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let performRequest: PerformRequest

    init(performRequest: @escaping PerformRequest = { try await URLSession.shared.data(for: $0) }) {
        self.performRequest = performRequest
    }

    func candidate(for source: TrackSource) async throws -> TrackCandidate {
        var components = URLComponents(string: "https://open.spotify.com/oembed")!
        components.queryItems = [
            URLQueryItem(name: "url", value: source.pageURL.absoluteString)
        ]
        let (data, response) = try await performRequest(URLRequest(url: components.url!))
        guard let http = response as? HTTPURLResponse else {
            throw TodAppError.trackUnavailable
        }
        switch http.statusCode {
        case 200:
            return try SpotifyOEmbedMapper.candidate(from: data, source: source)
        case 429:
            throw TodAppError.rateLimited
        default:
            throw TodAppError.trackUnavailable
        }
    }
}
