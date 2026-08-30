import Foundation

struct SpotifySearchRepository: MusicSearchRepository {
    typealias PerformRequest = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let tokenProvider: SpotifyTokenProvider
    private let performRequest: PerformRequest

    init(
        tokenProvider: SpotifyTokenProvider,
        performRequest: @escaping PerformRequest = { try await URLSession.shared.data(for: $0) }
    ) {
        self.tokenProvider = tokenProvider
        self.performRequest = performRequest
    }

    func searchTracks(matching query: String) async throws -> [TrackCandidate] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var components = URLComponents(string: "https://api.spotify.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "type", value: "track"),
            // Spotify's documented default/max is 50, but a Development Mode
            // app registration (the kind created from the dashboard without
            // an extended-quota request) rejects any `limit` above 10 with a
            // 400 "Invalid limit" -- confirmed empirically against the live
            // API with this project's own credentials. 10 is the largest
            // value that actually works for such an app.
            URLQueryItem(name: "limit", value: "10")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(try await tokenProvider.token())", forHTTPHeaderField: "Authorization")

        let (data, response) = try await performRequest(request)
        guard let http = response as? HTTPURLResponse else { throw TodAppError.trackUnavailable }
        guard http.statusCode != 429 else { throw TodAppError.rateLimited }
        // 401/403 mean the token itself was rejected -- a credentials problem,
        // not a track being unavailable. Name Secrets.xcconfig so a first-run
        // user with placeholder credentials is pointed at the right fix.
        guard http.statusCode != 401, http.statusCode != 403 else {
            throw TodAppError.missingSpotifyCredentials
        }
        guard http.statusCode == 200 else { throw TodAppError.trackUnavailable }

        return try SpotifyResponseMapper.candidates(from: data)
    }
}
