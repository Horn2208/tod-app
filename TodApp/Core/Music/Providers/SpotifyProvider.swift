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
    /// Falls back to the open iTunes catalog when there is no Spotify
    /// token, so search works without a music-service login.
    private let fallbackCatalog: ITunesCatalog?

    private var tokens: SpotifyTokens?
    private var declaredCapabilities: MusicProviderCapabilities = .none
    /// The one refresh several concurrent callers on an expired token share,
    /// rather than each firing its own -- Spotify may invalidate tokens when
    /// it sees a burst of identical refreshes.
    private var refreshInFlight: Task<String, Error>?
    /// Bumped by `signOut()`. `validToken()` captures the current value
    /// before starting a refresh, and `adopt(...)` checks it has not moved
    /// on before writing anything -- the guard against a refresh that
    /// outlives the sign-out that tried to cancel it. See `adopt(...)`.
    private var sessionGeneration = 0

    init(
        clientID: String,
        redirectURI: String = "todapp://auth/spotify",
        tokenStore: any TokenStore,
        exchange: SpotifyTokenExchange,
        performRequest: @escaping PerformRequest = { try await URLSession.shared.data(for: $0) },
        presentSignIn: @escaping PresentSignIn,
        fallbackCatalog: ITunesCatalog? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.clientID = clientID
        self.redirectURI = redirectURI
        self.tokenStore = tokenStore
        self.exchange = exchange
        self.performRequest = performRequest
        self.presentSignIn = presentSignIn
        self.fallbackCatalog = fallbackCatalog
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

    /// Brings a previous session back without asking again. Nobody is told
    /// when it does not work -- the sign-in screen is the answer either way.
    /// What the two failures differ in is what happens to the stored token.
    func restore() async {
        guard let refreshToken = try? tokenStore.read() else { return }
        do {
            let fresh = try await exchange.refresh(refreshToken)
            try? store(fresh, fallbackRefreshToken: refreshToken)
            await loadCapabilities()
        } catch TodAppError.authorizationFailed {
            // Spotify refuses this token: revoked, or the session ended.
            // Keeping it would mean trying it again on every launch.
            try? tokenStore.clear()
        } catch {
            // Offline, rate-limited, or Spotify having a moment -- none of
            // which says the session is over. This used to clear the token
            // for any failure at all, so a launch without network signed
            // people out and the next launch had nothing left to restore.
        }
    }

    func signOut() async {
        // Bumped first, synchronously, before anything below can suspend:
        // `adopt(...)` reads this to tell a refresh that belongs to this
        // session apart from one still settling from a session that has
        // since ended (Defect 4). Doing it first means every check that
        // runs later, and any refresh already in flight from before this
        // call, sees the new generation the moment it next asks.
        sessionGeneration += 1
        // Cancelling here is best-effort, not the actual guard: the
        // exchange's network call inside a refresh may not notice
        // `cancel()` before it finishes and calls back into `adopt(...)`
        // anyway. The generation check there is what actually stops it.
        refreshInFlight?.cancel()
        refreshInFlight = nil

        tokens = nil
        declaredCapabilities = .none
        try? tokenStore.clear()
    }

    func searchTracks(matching query: String) async throws -> [TrackCandidate] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        do {
            return try await searchOnSpotify(matching: trimmed)
        } catch TodAppError.authorizationFailed {
            // No Spotify token — fall back to the open iTunes catalog
            // so search works without a music-service login.
            guard let catalog = fallbackCatalog else { throw TodAppError.authorizationFailed }
            return try await catalog.search(title: trimmed, artist: "").map { song in
                TrackCandidate(
                    title: song.title,
                    artist: song.artist,
                    source: TrackSource(
                        service: .spotify,
                        serviceTrackID: song.id,
                        pageURL: song.pageURL ?? URL(string: "https://music.apple.com")!,
                        artworkURL: song.artworkURL
                    ),
                    durationSeconds: song.durationSeconds,
                    isrc: nil
                )
            }
        }
    }

    private func searchOnSpotify(matching query: String) async throws -> [TrackCandidate] {
        var components = URLComponents(string: "https://api.spotify.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
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

        // Captured now, before the network call: this is the session this
        // refresh belongs to, checked again in `adopt(...)` once the
        // refresh comes back.
        let generation = sessionGeneration
        let task = Task<String, Error> { [exchange, tokenStore] in
            // Nothing stored is a real "not signed in". A refresh that fails
            // on the network is not, so its own error travels on: otherwise
            // "Spotify is not reachable" reaches the user as "sign in again".
            guard let refreshToken = try? tokenStore.read() else {
                throw TodAppError.authorizationFailed
            }
            let fresh = try await exchange.refresh(refreshToken)
            return try self.adopt(fresh, fallbackRefreshToken: refreshToken, generation: generation)
        }
        refreshInFlight = task
        // Runs whether the task above returns or throws, so one failed
        // refresh does not leave every later call stuck awaiting a task that
        // has already finished failing.
        defer { refreshInFlight = nil }
        return try await task.value
    }

    /// Writes a refreshed token back only if the session it started in is
    /// still the current one. A refresh that was in flight when `signOut()`
    /// ran (Defect 4) finds `generation != sessionGeneration` here and is
    /// dropped instead of resurrecting a session the user already left --
    /// this is the actual guard; cancelling the task in `signOut()` is only
    /// a best effort, since the network call inside might not notice.
    ///
    /// A generation counter rather than a plain "signed out" flag: someone
    /// could sign in again while a stale refresh from the *previous* session
    /// is still settling, and a Bool cannot tell that new session apart from
    /// the one this refresh belongs to -- it would just read "signed in" and
    /// wrongly let the stale write through. A counter that only ever moves
    /// forward can tell them apart.
    private func adopt(_ fresh: SpotifyTokens, fallbackRefreshToken: String, generation: Int) throws -> String {
        guard generation == sessionGeneration else {
            throw TodAppError.authorizationFailed
        }
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
