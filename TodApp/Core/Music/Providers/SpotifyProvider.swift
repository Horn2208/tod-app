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
    /// Stops playback at the end of the picked section. Replaced whenever a
    /// new `play(_:from:)` starts, so a stale section can never stop a track
    /// that was just started.
    private var stopTask: Task<Void, Never>?
    /// The track this actor believes is playing right now, and the
    /// continuation `playbackUpdates()` currently feeds. Only this actor ever
    /// changes it -- in particular `stopTask` firing on its own clears it,
    /// which is the whole reason a consumer reads this instead of keeping its
    /// own play/stop flag.
    private var currentlyPlaying: TrackSource?
    private var playbackContinuation: AsyncStream<TrackSource?>.Continuation?

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
        // Checked before anything is sent: Spotify would answer 403
        // PREMIUM_REQUIRED, and a button that only fails is worse than one
        // that is not offered.
        guard declaredCapabilities.canPlayFullTracks else {
            throw TodAppError.playbackNotAvailable
        }
        guard try await hasActiveDevice() else { throw TodAppError.noActivePlaybackDevice }

        let token = try await validToken()
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/play")!)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "uris": ["spotify:track:\(source.serviceTrackID)"],
            "position_ms": Int((section?.start ?? 0) * 1000)
        ])
        let (_, response) = try await performRequest(request)

        // The capability check above should make this unreachable. If Spotify
        // says otherwise, it is right and our reading of the account was
        // wrong -- so the capability is withdrawn rather than argued with.
        if let http = response as? HTTPURLResponse, http.statusCode == 403 {
            declaredCapabilities.canPlayFullTracks = false
            declaredCapabilities.canStartAtPosition = false
            throw TodAppError.playbackNotAvailable
        }

        scheduleStop(after: section?.duration)
        setCurrentlyPlaying(source)
    }

    func stop() async {
        stopTask?.cancel()
        stopTask = nil
        setCurrentlyPlaying(nil)
        guard let token = try? await validToken() else { return }
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/pause")!)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try? await performRequest(request)
    }

    /// The current playback state, and every change to it from here on.
    /// Yields the state at the moment of subscription first, so a consumer
    /// that starts observing after playback already began still learns the
    /// truth immediately instead of waiting for the next change.
    ///
    /// Backed by a single continuation: this actor supports one long-lived
    /// consumer (`AppStore`), not a fan-out to several. Calling this again
    /// replaces that continuation rather than adding a second listener.
    func playbackUpdates() async -> AsyncStream<TrackSource?> {
        AsyncStream { continuation in
            playbackContinuation = continuation
            continuation.yield(currentlyPlaying)
        }
    }

    // MARK: - Private

    private struct Profile: Decodable { let product: String? }

    private struct DeviceList: Decodable {
        struct Device: Decodable { let is_active: Bool? }
        let devices: [Device]
    }

    /// Spotify plays on a device, not in this app. Without one it answers 404,
    /// which would otherwise reach the user as a plain "not found".
    ///
    /// Declared `throws` (rather than folding every outcome into the `Bool`)
    /// so a rejected session can be told apart from a genuinely absent
    /// device: throwing `.authorizationFailed` here means the call site in
    /// `play(...)` needs no change at all -- `guard try await
    /// hasActiveDevice() else { throw .noActivePlaybackDevice }` already
    /// reads correctly whichever way this fails.
    private func hasActiveDevice() async throws -> Bool {
        let token = try await validToken()
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/devices")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        // A network error carries no information about whether a device is
        // active, so it stays on the "no device" path -- vague, but not
        // wrong. Unlike a 401/403 below, it does not tell the user to do
        // something that will not help.
        guard let (data, response) = try? await performRequest(request) else { return false }

        // A rejected session is not "no device": it is a wrong instruction
        // waiting to happen. "No active device" tells the user to go open
        // Spotify on a phone or speaker: with an expired or revoked session,
        // that changes nothing, and they need to sign in again instead. So
        // this case is surfaced distinctly rather than lumped in below.
        if let http = response as? HTTPURLResponse, http.statusCode == 401 || http.statusCode == 403 {
            throw TodAppError.authorizationFailed
        }

        // An undecodable body is, like a network error, uninformative rather
        // than actively misleading -- staying on the "no device" path is
        // acceptable for the same reason.
        guard let list = try? JSONDecoder().decode(DeviceList.self, from: data) else {
            return false
        }
        return list.devices.contains { $0.is_active == true }
    }

    /// Replaces whatever stop timer was running, always -- even when nothing
    /// new is scheduled, so a stale timer from a previous `play(_:from:)`
    /// never survives to stop a track it knows nothing about. A section with
    /// no length (or none at all) plays to the end and schedules nothing: a
    /// zero-second `Task.sleep` would otherwise fire almost immediately and
    /// pause the track it was just told to start.
    private func scheduleStop(after duration: Double?) {
        stopTask?.cancel()
        guard let duration, duration > 0 else {
            stopTask = nil
            return
        }
        // A timer rather than polling the playback state every second: the
        // error is under a second and only affects when the music stops.
        // `[weak self]` so a pending timer never keeps the provider alive by
        // itself -- once nothing else references it, the timer sleeping in
        // the background is not a reason to.
        stopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            await self?.stop()
        }
    }

    /// Publishes to `playbackUpdates()` only on an actual change, so an
    /// idempotent `stop()` (nothing was playing) or a `play()` that starts
    /// the same track again does not spam a consumer with a repeat of the
    /// state it already has.
    private func setCurrentlyPlaying(_ track: TrackSource?) {
        guard track != currentlyPlaying else { return }
        currentlyPlaying = track
        playbackContinuation?.yield(track)
    }

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
