import Foundation
import Testing
@testable import TodApp

@Suite
struct SpotifyProviderAuthTests {
    private func provider(
        store: any TokenStore = InMemoryTokenStore(),
        product: String = "premium",
        meStatus: Int = 200,
        meBody: String? = nil,
        tokenStatus: Int = 200,
        callback: @escaping @Sendable (URL) -> URL = { url in
            let state = URLComponents(url: url, resolvingAgainstBaseURL: false)!
                .queryItems!.first { $0.name == "state" }!.value!
            return URL(string: "todapp://auth/spotify?code=abc123&state=\(state)")!
        }
    ) -> SpotifyProvider {
        SpotifyProvider(
            clientID: "client-123",
            redirectURI: "todapp://auth/spotify",
            tokenStore: store,
            exchange: SpotifyTokenExchange(
                clientID: "client-123",
                redirectURI: "todapp://auth/spotify",
                performRequest: { request in
                    (
                        Data(#"{"access_token":"at","refresh_token":"rt","expires_in":3600}"#.utf8),
                        HTTPURLResponse(url: request.url!, statusCode: tokenStatus,
                                        httpVersion: nil, headerFields: nil)!
                    )
                },
                now: { Date(timeIntervalSince1970: 0) }
            ),
            performRequest: { request in
                (
                    Data((meBody ?? #"{"product":"\#(product)"}"#).utf8),
                    HTTPURLResponse(url: request.url!, statusCode: meStatus,
                                    httpVersion: nil, headerFields: nil)!
                )
            },
            presentSignIn: { url, _ in callback(url) },
            now: { Date(timeIntervalSince1970: 0) }
        )
    }

    @Test
    func signingInStoresTheRefreshToken() async throws {
        let store = InMemoryTokenStore()

        try await provider(store: store).authorize()

        #expect(try store.read() == "rt")
    }

    /// `product` is the whole reason user-read-private is requested: it decides
    /// whether this account may be told to play at all.
    @Test
    func aPremiumAccountMayPlayAndSeek() async throws {
        let provider = provider(product: "premium")

        try await provider.authorize()

        let capabilities = await provider.capabilities
        #expect(capabilities.canSearch)
        #expect(capabilities.canPlayFullTracks)
        #expect(capabilities.canStartAtPosition)
        // The sound comes out of Spotify Connect, never out of this app.
        #expect(capabilities.playsInsideTheApp == false)
    }

    @Test
    func aFreeAccountMaySearchButNotPlay() async throws {
        let provider = provider(product: "free")

        try await provider.authorize()

        let capabilities = await provider.capabilities
        #expect(capabilities.canSearch)
        #expect(capabilities.canPlayFullTracks == false)
        #expect(capabilities.canStartAtPosition == false)
    }

    /// An unreadable profile must not be read as "premium" -- guessing
    /// generously here produces a button that answers 403.
    @Test
    func anUnreadableProfileGrantsNoPlayback() async throws {
        let provider = provider(meStatus: 500)

        try await provider.authorize()

        #expect(await provider.capabilities.canPlayFullTracks == false)
        #expect(await provider.isAuthorized)
    }

    /// Spotify's development mode lets five listed accounts in; anyone
    /// else gets a token and then this 403 (`docs/prompt.md`, item 21).
    @Test
    func anAccountOutsideSpotifysFiveIsToldSoAndNotKept() async {
        let store = InMemoryTokenStore()
        let provider = provider(
            store: store, meStatus: 403,
            meBody: "Check settings on developer.spotify.com/dashboard, the user may not be registered.")

        await #expect(throws: TodAppError.spotifyNotRegistered) {
            try await provider.authorize()
        }
        #expect(await provider.isAuthorized == false)
        #expect((try? store.read()) == nil)
    }

    @Test
    func aCancelledSignInLeavesNoToken() async {
        let store = InMemoryTokenStore()
        // Echoes the real state back with the error, the way an actual
        // Spotify redirect would: a fixed placeholder state would fail the
        // RFC 6749 state check first and report `.authorizationFailed`
        // instead of the cancellation this test means to exercise.
        let provider = provider(store: store, callback: { url in
            let state = URLComponents(url: url, resolvingAgainstBaseURL: false)!
                .queryItems!.first { $0.name == "state" }!.value!
            return URL(string: "todapp://auth/spotify?error=access_denied&state=\(state)")!
        })

        await #expect(throws: TodAppError.authorizationCancelled) {
            try await provider.authorize()
        }
        // Parenthesised: `try?` binds to the whole `== nil` comparison
        // otherwise, producing `Bool?` instead of `Bool` (SE-0230 flattening
        // applies to `try? store.read()` alone, not to a wider expression).
        #expect((try? store.read()) == nil)
        #expect(await provider.isAuthorized == false)
    }

    @Test
    func signingOutForgetsTheToken() async throws {
        let store = InMemoryTokenStore()
        let provider = provider(store: store)
        try await provider.authorize()

        await provider.signOut()

        #expect(try store.read() == nil)
        #expect(await provider.isAuthorized == false)
        #expect(await provider.capabilities == .none)
    }

    /// Defect 4, the worst of the five: a refresh already in flight when
    /// `signOut()` runs must not resurrect the session once it finally
    /// settles. Cancelling the task is not enough on its own to prove this --
    /// the exchange's network call inside might not notice `cancel()` before
    /// it returns a perfectly good token -- so this pins the outcome that
    /// actually matters (still signed out, nothing written) rather than the
    /// mechanism.
    @Test
    func signingOutDuringARefreshDoesNotSignBackIn() async throws {
        let store = InMemoryTokenStore(stored: "rt-1")
        let provider = SpotifyProvider(
            clientID: "client-123",
            tokenStore: store,
            exchange: SpotifyTokenExchange(
                clientID: "client-123",
                redirectURI: "todapp://auth/spotify",
                performRequest: { request in
                    // A few tens of milliseconds: long enough that signOut()
                    // below is certain to run while this refresh is still
                    // in flight.
                    try? await Task.sleep(for: .milliseconds(30))
                    return (
                        Data(#"{"access_token":"at","refresh_token":"rt-2","expires_in":3600}"#.utf8),
                        HTTPURLResponse(url: request.url!, statusCode: 200,
                                        httpVersion: nil, headerFields: nil)!
                    )
                },
                now: { Date(timeIntervalSince1970: 0) }
            ),
            performRequest: { request in
                (
                    Data(#"{"product":"premium"}"#.utf8),
                    HTTPURLResponse(url: request.url!, statusCode: 200,
                                    httpVersion: nil, headerFields: nil)!
                )
            },
            presentSignIn: { _, _ in URL(string: "todapp://auth/spotify")! },
            now: { Date(timeIntervalSince1970: 0) }
        )

        // No cached token yet, so this goes straight through validToken()'s
        // refresh path -- which the mock above holds open for 30ms.
        async let search: [TrackCandidate]? = try? provider.searchTracks(matching: "x")
        try await Task.sleep(for: .milliseconds(5))

        await provider.signOut()
        _ = await search // let the stale refresh finish settling before asserting

        #expect(await provider.isAuthorized == false)
        #expect(await provider.capabilities == .none)
        #expect(try store.read() == nil)
    }

    /// A stored token is what makes the second launch skip the sign-in screen.
    @Test
    func aStoredTokenIsRestoredWithoutAskingAgain() async throws {
        let provider = provider(store: InMemoryTokenStore(stored: "rt-old"))

        await provider.restore()

        #expect(await provider.isAuthorized)
        #expect(await provider.capabilities.canPlayFullTracks)
    }

    /// A launch without network used to end the session: any failed refresh
    /// cleared the stored token, so the launch after that had nothing left to
    /// restore and the sign-in screen was back for good.
    @Test
    func aRestoreThatCannotReachSpotifyKeepsTheStoredToken() async throws {
        let store = InMemoryTokenStore(stored: "rt-old")
        let provider = provider(store: store, tokenStatus: 503)

        await provider.restore()

        #expect(await provider.isAuthorized == false)
        #expect(try store.read() == "rt-old")
    }

    /// A token Spotify itself refuses is worth nothing, and keeping it would
    /// mean trying it again on every launch.
    @Test
    func aRestoreSpotifyRefusesClearsTheStoredToken() async throws {
        let store = InMemoryTokenStore(stored: "rt-old")
        let provider = provider(store: store, tokenStatus: 400)

        await provider.restore()

        #expect(try store.read() == nil)
    }

    @Test
    func nothingStoredMeansSignedOut() async {
        let provider = provider(store: InMemoryTokenStore())

        await provider.restore()

        #expect(await provider.isAuthorized == false)
    }

    /// A Keychain write failure during sign-in must not leave the provider
    /// looking authorized while the caller was told sign-in failed -- that
    /// combination is worse than simply staying signed out.
    @Test
    func aFailedTokenWriteLeavesTheProviderNotAuthorized() async {
        let provider = provider(store: TokenStoreThatFailsToWrite())

        await #expect(throws: TodAppError.tokenStorageFailed) {
            try await provider.authorize()
        }
        #expect(await provider.isAuthorized == false)
    }

    /// Same failure, checked from the capabilities side: they must read as
    /// `.none`, matching signed-out, rather than something left over from a
    /// partial sign-in that never reached `loadCapabilities()`.
    @Test
    func aFailedTokenWriteLeavesCapabilitiesNone() async {
        let provider = provider(store: TokenStoreThatFailsToWrite())

        await #expect(throws: TodAppError.tokenStorageFailed) {
            try await provider.authorize()
        }
        #expect(await provider.capabilities == .none)
    }
}
