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
        now: @escaping @Sendable () -> Date = { Date() }
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

    /// `application/x-www-form-urlencoded`, written out by hand.
    ///
    /// `URLComponents` used to do this, and it encodes for a URL's query
    /// rather than for a form body: `+`, `&` and `=` are all legal in a query
    /// and pass through untouched. In a form body `+` means a space and a
    /// stray `&` splits one value into two fields -- so a code or token
    /// carrying either would reach Spotify as something else, or tear the
    /// body apart.
    private static let formAllowed: CharacterSet = {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return allowed
    }()

    private static func formEncoded(_ fields: [String: String]) -> Data {
        // Sorted, so the same fields always make the same body: a test can
        // read it, and two requests differ only where they really differ.
        let pairs = fields.sorted { $0.key < $1.key }.map { key, value in
            "\(escaped(key))=\(escaped(value))"
        }
        return Data(pairs.joined(separator: "&").utf8)
    }

    private static func escaped(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: formAllowed) ?? text
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
        request.httpBody = Self.formEncoded(fields)

        let (data, response) = try await performRequest(request)
        guard let http = response as? HTTPURLResponse else {
            throw TodAppError.network(underlying: URLError(.badServerResponse))
        }
        switch http.statusCode {
        case 200:
            break
        // Spotify answers a revoked or expired grant with 400 invalid_grant.
        // These three are the only answers that mean the session is over.
        case 400, 401, 403:
            throw TodAppError.authorizationFailed
        case 429:
            throw TodAppError.rateLimited
        // A 500, or anything else, says nothing about whether this token is
        // still good. Calling it an authorization failure is how a bad minute
        // of network turned into a sign-out -- see `SpotifyProvider.restore()`.
        default:
            throw TodAppError.network(underlying: URLError(.badServerResponse))
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw TodAppError.network(underlying: URLError(.cannotParseResponse))
        }
        let lifetime = decoded.expires_in ?? 3600
        return SpotifyTokens(
            accessToken: decoded.access_token,
            refreshToken: decoded.refresh_token,
            expiresAt: now().addingTimeInterval(max(0, lifetime - Self.safetyMargin))
        )
    }
}
