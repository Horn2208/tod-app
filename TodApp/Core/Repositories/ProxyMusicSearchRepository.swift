import Foundation

/// Searches through a serverless function that holds the Spotify client secret,
/// so the app itself ships without one. Same protocol as
/// `SpotifySearchRepository`: swapping them is one line in `AppStore`.
///
/// The proxy answers `GET <base>/search?q=<query>` with Spotify's own search
/// body, unchanged. That keeps one mapper and one recorded fixture on this side
/// rather than inventing a second wire format to keep in sync.
struct ProxyMusicSearchRepository: MusicSearchRepository {
    typealias PerformRequest = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let baseURL: URL
    private let performRequest: PerformRequest

    init(
        baseURL: URL,
        performRequest: @escaping PerformRequest = { try await URLSession.shared.data(for: $0) }
    ) {
        self.baseURL = baseURL
        self.performRequest = performRequest
    }

    func searchTracks(matching query: String) async throws -> [TrackCandidate] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("search"),
            resolvingAgainstBaseURL: false
        ) else { throw TodAppError.searchUnavailable }
        components.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        guard let url = components.url else { throw TodAppError.searchUnavailable }

        // Deliberately no Authorization header: the app has nothing to send,
        // which is the entire reason the proxy exists.
        let (data, response) = try await performRequest(URLRequest(url: url))

        guard let http = response as? HTTPURLResponse else { throw TodAppError.searchUnavailable }
        switch http.statusCode {
        case 200:
            return try SpotifyResponseMapper.candidates(from: data)
        case 429:
            throw TodAppError.rateLimited
        // 401/403 means the proxy's own credentials were rejected and 5xx means
        // it is down -- both are server-side, and neither is something the
        // person searching can fix.
        case 401, 403, 500...599:
            throw TodAppError.searchUnavailable
        default:
            throw TodAppError.trackUnavailable
        }
    }
}
