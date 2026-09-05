import Foundation

/// Spotify behind the provider door. An actor because the token and the
/// capabilities are mutable state that several screens read at once.
actor SpotifyProvider: MusicProvider {
    typealias PerformRequest = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    /// Opens the sign-in sheet and returns the callback URL. Injected so the
    /// tests never touch AuthenticationServices.
    typealias PresentSignIn = @Sendable (URL, String) async throws -> URL

    nonisolated let service: MusicService = .spotify

    private let clientID: String
    private let redirectURI: String
    private let tokenStore: any TokenStore
    private let exchange: SpotifyTokenExchange
    private let performRequest: PerformRequest
    private let presentSignIn: PresentSignIn
    private let now: @Sendable () -> Date

    private var tokens: SpotifyTokens?
    private var declaredCapabilities: MusicProviderCapabilities = .none
    /// The one refresh several concurrent callers on an expired token share,
    /// rather than each firing its own -- Spotify may invalidate tokens when
    /// it sees a burst of identical refreshes.
    private var refreshInFlight: Task<String, Error>?

    init(
        clientID: String,
        redirectURI: String = "todapp://auth/spotify",
        tokenStore: any TokenStore,
        exchange: SpotifyTokenExchange,
        performRequest: @escaping PerformRequest = { try await URLSession.shared.data(for: $0) },
        presentSignIn: @escaping PresentSignIn,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.clientID = clientID
        self.redirectURI = redirectURI
        self.tokenStore = tokenStore
        self.exchange = exchange
        self.performRequest = performRequest
        self.presentSignIn = presentSignIn
        self.now = now
    }

    var isAuthorized: Bool { tokens != nil }
    var capabilities: MusicProviderCapabilities { declaredCapabilities }

    func authorize() async throws {
        let verifier = PKCE.makeVerifier()
        let state = PKCE.makeState()
        let request = SpotifyAuthorizationRequest(
            clientID: clientID, redirectURI: redirectURI, verifier: verifier, state: state
        )

        let callback = try await presentSignIn(request.url, scheme(of: redirectURI))
        let code = try SpotifyAuthorizationRequest.code(from: callback, expectedState: state)

        let fresh = try await exchange.exchange(code: code, verifier: verifier)
        try store(fresh)
        await loadCapabilities()
    }

    /// Brings a previous session back without asking again. A refresh that
    /// fails simply means signed out -- there is nothing to report to anyone.
    func restore() async {
        guard let refreshToken = try? tokenStore.read() else { return }
        guard let fresh = try? await exchange.refresh(refreshToken) else {
            try? tokenStore.clear()
            return
        }
        try? store(fresh, fallbackRefreshToken: refreshToken)
        await loadCapabilities()
    }

    func signOut() async {
        tokens = nil
        declaredCapabilities = .none
        try? tokenStore.clear()
    }

    func searchTracks(matching query: String) async throws -> [TrackCandidate] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var components = URLComponents(string: "https://api.spotify.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "type", value: "track"),
            // A Development Mode app registration refuses any limit above 10.
            URLQueryItem(name: "limit", value: "10")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(try await validToken())", forHTTPHeaderField: "Authorization")

        let (data, response) = try await performRequest(request)
        guard let http = response as? HTTPURLResponse else { throw TodAppError.searchUnavailable }
        switch http.statusCode {
        case 200: return try SpotifyResponseMapper.candidates(from: data)
        case 429: throw TodAppError.rateLimited
        // The app holds no credentials of its own any more, so a refused token
        // means this person needs to sign in again.
        case 401, 403: throw TodAppError.authorizationFailed
        default: throw TodAppError.trackUnavailable
        }
    }

    func play(_ source: TrackSource, from section: TrackSection?) async throws {
        // Filled in by Task 8.
        throw TodAppError.playbackNotAvailable
    }

    func stop() async {}

    // MARK: - Private

    private struct Profile: Decodable { let product: String? }

    /// Reads `product` to decide what this account may do. An unreadable
    /// profile grants nothing: guessing generously here produces a button that
    /// answers 403.
    private func loadCapabilities() async {
        guard let token = tokens?.accessToken else {
            declaredCapabilities = .none
            return
        }
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        var premium = false
        if let (data, response) = try? await performRequest(request),
           let http = response as? HTTPURLResponse, http.statusCode == 200,
           let profile = try? JSONDecoder().decode(Profile.self, from: data) {
            premium = profile.product == "premium"
        }
        declaredCapabilities = MusicProviderCapabilities(
            canSearch: true,
            canPlayFullTracks: premium,
            canStartAtPosition: premium,
            playsInsideTheApp: false
        )
    }

    /// Renews an expired token before it is used, so a long session does not
    /// start failing halfway through. Several screens can ask at once on a
    /// cold token; the first caller's work is what the others await, or
    /// Spotify sees a burst of identical refreshes and may invalidate them.
    private func validToken() async throws -> String {
        if let current = tokens, current.expiresAt > now() { return current.accessToken }
        if let refreshInFlight { return try await refreshInFlight.value }

        let task = Task<String, Error> { [exchange, tokenStore] in
            guard let refreshToken = try? tokenStore.read(),
                  let fresh = try? await exchange.refresh(refreshToken) else {
                throw TodAppError.authorizationFailed
            }
            return try self.adopt(fresh, fallbackRefreshToken: refreshToken)
        }
        refreshInFlight = task
        // Runs whether the task above returns or throws, so one failed
        // refresh does not leave every later call stuck awaiting a task that
        // has already finished failing.
        defer { refreshInFlight = nil }
        return try await task.value
    }

    private func adopt(_ fresh: SpotifyTokens, fallbackRefreshToken: String) throws -> String {
        try store(fresh, fallbackRefreshToken: fallbackRefreshToken)
        return fresh.accessToken
    }

    private func store(_ fresh: SpotifyTokens, fallbackRefreshToken: String? = nil) throws {
        // Persist first, adopt second. `authorize()` calls this with `try`,
        // not `try?`, so a throw here propagates to the caller as a failed
        // sign-in. If `tokens` were assigned before the write and the write
        // then threw, `isAuthorized` would read `true` while the caller was
        // just told sign-in failed and `loadCapabilities()` never ran --
        // a provider that looks signed in from the outside and is empty on
        // the inside. Failing to persist and staying unauthenticated is the
        // coherent outcome; looking authenticated while unable to persist is
        // worse than simply not being signed in, so this order is not
        // incidental and should not be "simplified" back.
        //
        // A refresh may answer without a new refresh token; the old one keeps
        // working, and overwriting it with nothing would sign the user out.
        if let refreshToken = fresh.refreshToken ?? fallbackRefreshToken {
            try tokenStore.write(refreshToken)
        }
        tokens = fresh
    }

    private func scheme(of uri: String) -> String {
        URLComponents(string: uri)?.scheme ?? "todapp"
    }
}
