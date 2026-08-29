import Foundation

/// SoundCloud's oEmbed endpoint is public and needs no API key -- which matters,
/// because SoundCloud no longer grants API credentials on request.
enum SoundCloudOEmbedMapper {
    struct Response: Decodable {
        let title: String
        let author_name: String
        let thumbnail_url: String?
    }

    static func candidate(from data: Data, source: TrackSource) throws -> TrackCandidate {
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        var resolved = source
        resolved.artworkURL = decoded.thumbnail_url.flatMap { URL(string: $0) }
        return TrackCandidate(title: decoded.title, artist: decoded.author_name, source: resolved)
    }
}

struct SoundCloudOEmbedClient: Sendable {
    typealias PerformRequest = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let performRequest: PerformRequest

    init(performRequest: @escaping PerformRequest = { try await URLSession.shared.data(for: $0) }) {
        self.performRequest = performRequest
    }

    func candidate(for source: TrackSource) async throws -> TrackCandidate {
        var components = URLComponents(string: "https://soundcloud.com/oembed")!
        components.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "url", value: source.pageURL.absoluteString)
        ]
        let (data, response) = try await performRequest(URLRequest(url: components.url!))
        guard let http = response as? HTTPURLResponse else {
            throw TodAppError.trackUnavailable
        }
        switch http.statusCode {
        case 200:
            return try SoundCloudOEmbedMapper.candidate(from: data, source: source)
        case 429:
            throw TodAppError.rateLimited
        default:
            throw TodAppError.trackUnavailable
        }
    }
}
