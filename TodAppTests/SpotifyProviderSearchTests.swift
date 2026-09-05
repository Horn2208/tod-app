import Foundation
import Testing
@testable import TodApp

@Suite
struct SpotifyProviderSearchTests {
    private let body = #"""
    {"tracks":{"items":[
      {"id":"4cOdK2wGLETKBW3PvgPWqT","name":"As It Was","duration_ms":167000,
       "artists":[{"name":"Harry Styles"}],
       "external_urls":{"spotify":"https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT"},
       "album":{"images":[{"url":"https://i.scdn.co/image/medium","width":300}]}}
    ]}}
    """#

    private func signedIn(
        status: Int = 200,
        body: String? = nil,
        onRequest: (@Sendable (URLRequest) -> Void)? = nil
    ) async throws -> SpotifyProvider {
        let payload = body ?? self.body
        let provider = SpotifyProvider(
            clientID: "client-123",
            tokenStore: InMemoryTokenStore(),
            exchange: SpotifyTokenExchange(
                clientID: "client-123",
                redirectURI: "todapp://auth/spotify",
                performRequest: { request in
                    (
                        Data(#"{"access_token":"at","refresh_token":"rt","expires_in":3600}"#.utf8),
                        HTTPURLResponse(url: request.url!, statusCode: 200,
                                        httpVersion: nil, headerFields: nil)!
                    )
                },
                now: { Date(timeIntervalSince1970: 0) }
            ),
            performRequest: { request in
                onRequest?(request)
                let path = request.url?.path ?? ""
                if path == "/v1/me" {
                    return (
                        Data(#"{"product":"premium"}"#.utf8),
                        HTTPURLResponse(url: request.url!, statusCode: 200,
                                        httpVersion: nil, headerFields: nil)!
                    )
                }
                return (
                    Data(payload.utf8),
                    HTTPURLResponse(url: request.url!, statusCode: status,
                                    httpVersion: nil, headerFields: nil)!
                )
            },
            presentSignIn: { url, _ in
                let state = URLComponents(url: url, resolvingAgainstBaseURL: false)!
                    .queryItems!.first { $0.name == "state" }!.value!
                return URL(string: "todapp://auth/spotify?code=abc123&state=\(state)")!
            },
            now: { Date(timeIntervalSince1970: 0) }
        )
        try await provider.authorize()
        return provider
    }

    @Test
    func aBlankQueryReturnsNothingWithoutAskingSpotify() async throws {
        let provider = try await signedIn(onRequest: { request in
            if request.url?.path == "/v1/search" {
                Issue.record("must not search for a blank query")
            }
        })

        #expect(try await provider.searchTracks(matching: "   ").isEmpty)
    }

    @Test
    func searchesWithTheUserTokenAndMapsTheAnswer() async throws {
        let box = RequestBox()
        let provider = try await signedIn(onRequest: { request in
            if request.url?.path == "/v1/search" { box.store(request) }
        })

        let results = try await provider.searchTracks(matching: "as it was")

        #expect(results.count == 1)
        #expect(results[0].title == "As It Was")
        #expect(results[0].durationSeconds == 167)

        let request = try #require(box.value)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer at")
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
        #expect(items.first { $0.name == "q" }?.value == "as it was")
        #expect(items.first { $0.name == "type" }?.value == "track")
    }

    @Test
    func tooManyRequestsIsReportedAsRateLimited() async throws {
        let provider = try await signedIn(status: 429, body: "{}")

        await #expect(throws: TodAppError.rateLimited) {
            try await provider.searchTracks(matching: "x")
        }
    }

    /// A rejected token is a sign-in problem now, not a missing Secrets file --
    /// the app ships without one.
    @Test
    func aRejectedTokenIsReportedAsAnAuthorizationFailure() async throws {
        let provider = try await signedIn(status: 401, body: "{}")

        await #expect(throws: TodAppError.authorizationFailed) {
            try await provider.searchTracks(matching: "x")
        }
    }

    /// The spec promises one refresh, not one per caller. Two searches on an
    /// expired token must produce a single call to the token endpoint.
    ///
    /// The exchange's clock is deliberately far behind the provider's: the
    /// token `restore()` fetches computes its `expiresAt` from the exchange's
    /// clock (epoch 0 + a ~1-hour lifetime), which the provider's own clock
    /// (fixed at epoch 10_000) already reads as being in the past. Without
    /// that gap both clocks would agree the token restore() just fetched is
    /// still fresh, neither search would need to refresh at all, and
    /// `refreshes.count` would sit at 0 -- a passing assertion that proves
    /// nothing about single-flight. With the gap, both concurrent searches
    /// genuinely hit `validToken()`'s refresh path.
    @Test
    func concurrentSearchesOnAnExpiredTokenRefreshOnce() async throws {
        let refreshes = Counter()
        let provider = SpotifyProvider(
            clientID: "client-123",
            tokenStore: InMemoryTokenStore(stored: "rt-1"),
            exchange: SpotifyTokenExchange(
                clientID: "client-123",
                redirectURI: "todapp://auth/spotify",
                performRequest: { request in
                    refreshes.increment()
                    // Long enough that both concurrent searches are certain
                    // to have reached validToken() before this resolves --
                    // proof the second caller awaits the first's task rather
                    // than starting a second refresh of its own.
                    try? await Task.sleep(for: .milliseconds(20))
                    return (
                        Data(#"{"access_token":"at","refresh_token":"rt","expires_in":3600}"#.utf8),
                        HTTPURLResponse(url: request.url!, statusCode: 200,
                                        httpVersion: nil, headerFields: nil)!
                    )
                },
                now: { Date(timeIntervalSince1970: 0) }
            ),
            performRequest: { [searchBody = body] request in
                let body = request.url?.path == "/v1/me" ? #"{"product":"premium"}"# : searchBody
                return (
                    Data(body.utf8),
                    HTTPURLResponse(url: request.url!, statusCode: 200,
                                    httpVersion: nil, headerFields: nil)!
                )
            },
            presentSignIn: { _, _ in URL(string: "todapp://auth/spotify")! },
            now: { Date(timeIntervalSince1970: 10_000) }
        )
        await provider.restore()
        refreshes.reset()

        async let first = provider.searchTracks(matching: "a")
        async let second = provider.searchTracks(matching: "b")
        _ = try await (first, second)

        // Exactly one, not merely "at most one": the clock gap above
        // guarantees a refresh was actually needed, so a passing `== 1`
        // shows both single-flight held (not 2) and the refresh path was
        // truly exercised (not 0).
        #expect(refreshes.count == 1)
    }

    /// `refreshInFlight` must be cleared once the shared task settles even
    /// when it throws -- otherwise the one caller who happened to trigger a
    /// failing refresh poisons every later call, which would keep re-awaiting
    /// that same failed task instead of trying again.
    @Test
    func aFailedRefreshDoesNotPoisonTheNextCall() async throws {
        let attempts = Counter()
        let provider = SpotifyProvider(
            clientID: "client-123",
            tokenStore: InMemoryTokenStore(stored: "rt-1"),
            exchange: SpotifyTokenExchange(
                clientID: "client-123",
                redirectURI: "todapp://auth/spotify",
                performRequest: { request in
                    attempts.increment()
                    if attempts.count == 1 {
                        // The first refresh attempt fails (e.g. Spotify
                        // hiccups or the network drops mid-request).
                        return (
                            Data("{}".utf8),
                            HTTPURLResponse(url: request.url!, statusCode: 400,
                                            httpVersion: nil, headerFields: nil)!
                        )
                    }
                    return (
                        Data(#"{"access_token":"at","refresh_token":"rt","expires_in":3600}"#.utf8),
                        HTTPURLResponse(url: request.url!, statusCode: 200,
                                        httpVersion: nil, headerFields: nil)!
                    )
                },
                now: { Date(timeIntervalSince1970: 0) }
            ),
            performRequest: { [body] request in
                (
                    Data(body.utf8),
                    HTTPURLResponse(url: request.url!, statusCode: 200,
                                    httpVersion: nil, headerFields: nil)!
                )
            },
            presentSignIn: { _, _ in URL(string: "todapp://auth/spotify")! },
            now: { Date(timeIntervalSince1970: 10_000) }
        )

        // No token yet, so the first search must attempt a refresh -- which fails.
        await #expect(throws: TodAppError.authorizationFailed) {
            try await provider.searchTracks(matching: "x")
        }
        #expect(attempts.count == 1)

        // If refreshInFlight had not been cleared, this would re-await the
        // same failed task and throw again without calling performRequest a
        // second time. It must instead attempt a fresh refresh and succeed.
        let results = try await provider.searchTracks(matching: "x")
        #expect(results.count == 1)
        #expect(attempts.count == 2)
    }
}

/// Counts calls from a Sendable closure.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func increment() {
        lock.lock(); defer { lock.unlock() }
        value += 1
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        value = 0
    }
}
