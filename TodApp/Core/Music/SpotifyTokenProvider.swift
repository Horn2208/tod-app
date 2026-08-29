import Foundation

/// Holds the client-credentials token. An actor so that parallel searches
/// share one token instead of each fetching their own.
actor SpotifyTokenProvider {
    typealias Fetch = @Sendable (SpotifyCredentials) async throws -> (token: String, expiresIn: TimeInterval)

    private let credentials: SpotifyCredentials
    private let now: @Sendable () -> Date
    private let fetch: Fetch

    private var cached: (token: String, expiresAt: Date)?

    /// The in-flight fetch, if any. Lets concurrent callers that arrive on a
    /// cold cache await the same request instead of each starting their own --
    /// without this, the actor only partly delivers on its stated purpose of
    /// sharing one token across parallel searches.
    private var pendingFetch: Task<(token: String, expiresIn: TimeInterval), Error>?

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

        if let pendingFetch {
            // A fetch is already underway (started by another caller that
            // also found a cold cache) -- await it instead of starting a
            // second one.
            return try await pendingFetch.value.token
        }

        let task = Task { try await fetch(credentials) }
        pendingFetch = task

        do {
            let result = try await task.value
            pendingFetch = nil
            let expiresAt = now().addingTimeInterval(max(0, result.expiresIn - safetyMargin))
            cached = (result.token, expiresAt)
            return result.token
        } catch {
            // Clear the pending task on failure too, so a failed fetch
            // doesn't permanently wedge every later caller onto a task that
            // will only ever throw.
            pendingFetch = nil
            throw error
        }
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
