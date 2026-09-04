import Foundation

struct SpotifyTokens: Equatable, Sendable {
    var accessToken: String
    /// Nil when a refresh answered without a new one -- the old one stays valid.
    var refreshToken: String?
    var expiresAt: Date
}

/// Trades an authorization code for tokens, and later a refresh token for a
/// fresh one. No client secret is involved: with PKCE the verifier is the proof.
struct SpotifyTokenExchange: Sendable {
    typealias PerformRequest = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    /// Expire a little early so a request cannot leave with a token that dies
    /// in flight -- the same margin SpotifyTokenProvider used.
    private static let safetyMargin: TimeInterval = 30

    private let clientID: String
    private let redirectURI: String
    private let performRequest: PerformRequest
    private let now: @Sendable () -> Date

    init(
        clientID: String,
        redirectURI: String,
        performRequest: @escaping PerformRequest = { try await URLSession.shared.data(for: $0) },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.clientID = clientID
        self.redirectURI = redirectURI
        self.performRequest = performRequest
        self.now = now
    }

    func exchange(code: String, verifier: String) async throws -> SpotifyTokens {
        try await post([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientID,
            "code_verifier": verifier
        ])
    }

    func refresh(_ refreshToken: String) async throws -> SpotifyTokens {
        try await post([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID
        ])
    }

    private struct Response: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Double?
    }

    private func post(_ fields: [String: String]) async throws -> SpotifyTokens {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = Data((body.percentEncodedQuery ?? "").utf8)

        let (data, response) = try await performRequest(request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw TodAppError.authorizationFailed
        }
        let lifetime = decoded.expires_in ?? 3600
        return SpotifyTokens(
            accessToken: decoded.access_token,
            refreshToken: decoded.refresh_token,
            expiresAt: now().addingTimeInterval(max(0, lifetime - Self.safetyMargin))
        )
    }
}
