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
            URLQueryItem(name: "limit", value: "20")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(try await tokenProvider.token())", forHTTPHeaderField: "Authorization")

        let (data, response) = try await performRequest(request)
        guard let http = response as? HTTPURLResponse else { throw TodAppError.trackUnavailable }
        guard http.statusCode != 429 else { throw TodAppError.rateLimited }
        guard http.statusCode == 200 else { throw TodAppError.trackUnavailable }

        return try SpotifyResponseMapper.candidates(from: data)
    }
}
