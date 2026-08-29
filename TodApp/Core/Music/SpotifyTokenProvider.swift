import Foundation

/// Holds the client-credentials token. An actor so that parallel searches
/// share one token instead of each fetching their own.
actor SpotifyTokenProvider {
    typealias Fetch = @Sendable (SpotifyCredentials) async throws -> (token: String, expiresIn: TimeInterval)

    private let credentials: SpotifyCredentials
    private let now: @Sendable () -> Date
    private let fetch: Fetch

    private var cached: (token: String, expiresAt: Date)?

    /// Renew slightly early so a request never travels with a token that
    /// expires in flight.
    private let safetyMargin: TimeInterval = 30

    init(
        credentials: SpotifyCredentials,
        now: @escaping @Sendable () -> Date = { Date() },
        fetch: @escaping Fetch = SpotifyTokenProvider.liveFetch
    ) {
        self.credentials = credentials
        self.now = now
        self.fetch = fetch
    }

    func token() async throws -> String {
        if let cached, cached.expiresAt > now() {
            return cached.token
        }
        let result = try await fetch(credentials)
        let expiresAt = now().addingTimeInterval(max(0, result.expiresIn - safetyMargin))
        cached = (result.token, expiresAt)
        return result.token
    }

    static let liveFetch: Fetch = { credentials in
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let pair = "\(credentials.clientID):\(credentials.clientSecret)"
        let encoded = Data(pair.utf8).base64EncodedString()
        request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
        request.httpBody = Data("grant_type=client_credentials".utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TodAppError.trackUnavailable }
        guard http.statusCode != 429 else { throw TodAppError.rateLimited }
        guard http.statusCode == 200 else { throw TodAppError.missingSpotifyCredentials }

        struct TokenResponse: Decodable {
            let access_token: String
            let expires_in: TimeInterval
        }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        return (decoded.access_token, decoded.expires_in)
    }
}
