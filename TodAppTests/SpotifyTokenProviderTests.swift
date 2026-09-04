import Foundation
import Testing
@testable import TodApp

@Suite
struct SpotifyTokenProviderTests {
    private let credentials = SpotifyCredentials(clientID: "id", clientSecret: "secret")

    @Test
    func reusesTokenWhileItIsStillValid() async throws {
        let counter = CallCounter()
        let provider = SpotifyTokenProvider(
            credentials: credentials,
            now: { Date(timeIntervalSince1970: 0) },
            fetch: { _ in await counter.increment(); return ("token-1", 3600) }
        )

        let first = try await provider.token()
        let second = try await provider.token()

        #expect(first == "token-1")
        #expect(second == "token-1")
        #expect(await counter.count == 1)
    }

    @Test
    func fetchesAgainOnceTheTokenHasExpired() async throws {
        let counter = CallCounter()
        let clock = MutableClock(now: Date(timeIntervalSince1970: 0))
        let provider = SpotifyTokenProvider(
            credentials: credentials,
            now: { clock.current },
            fetch: { _ in
                let n = await counter.increment()
                return ("token-\(n)", 3600)
            }
        )

        _ = try await provider.token()
        // 3600 - safetyMargin: the moment the cached token stops counting.
        clock.current = Date(timeIntervalSince1970: 3570)
        let second = try await provider.token()

        #expect(second == "token-2")
        #expect(await counter.count == 2)
    }

    /// The margin exists so a request never leaves with a token that dies in
    /// flight. Moving the clock to the nominal 3600 would pass with or without
    /// it; these two cases sit either side of the effective expiry and fail if
    /// the margin is dropped.
    @Test
    func renewsBeforeTheNominalExpiryAndNotOneSecondEarlier() async throws {
        let counter = CallCounter()
        let clock = MutableClock(now: Date(timeIntervalSince1970: 0))
        let provider = SpotifyTokenProvider(
            credentials: credentials,
            now: { clock.current },
            fetch: { _ in
                let n = await counter.increment()
                return ("token-\(n)", 3600)
            }
        )
        _ = try await provider.token()

        clock.current = Date(timeIntervalSince1970: 3569)
        #expect(try await provider.token() == "token-1")
        #expect(await counter.count == 1)

        clock.current = Date(timeIntervalSince1970: 3580)  // still short of 3600
        #expect(try await provider.token() == "token-2")
        #expect(await counter.count == 2)
    }

    @Test
    func concurrentCallersOnAColdCacheShareASingleFetch() async throws {
        let counter = CallCounter()
        let provider = SpotifyTokenProvider(
            credentials: credentials,
            now: { Date(timeIntervalSince1970: 0) },
            fetch: { _ in
                let n = await counter.increment()
                // Hold the fetch open briefly so both callers are guaranteed
                // to arrive on the actor while the cache is still cold.
                try await Task.sleep(nanoseconds: 50_000_000)
                return ("token-\(n)", 3600)
            }
        )

        async let first = provider.token()
        async let second = provider.token()
        let (firstToken, secondToken) = try await (first, second)

        #expect(firstToken == secondToken)
        #expect(await counter.count == 1)
    }

    @Test
    func aFailedFetchDoesNotWedgeLaterCalls() async throws {
        let counter = CallCounter()
        let provider = SpotifyTokenProvider(
            credentials: credentials,
            now: { Date(timeIntervalSince1970: 0) },
            fetch: { _ in
                let n = await counter.increment()
                if n == 1 {
                    throw TodAppError.rateLimited
                }
                return ("token-\(n)", 3600)
            }
        )

        await #expect(throws: TodAppError.rateLimited) {
            try await provider.token()
        }

        let second = try await provider.token()

        #expect(second == "token-2")
        #expect(await counter.count == 2)
    }
}

actor CallCounter {
    private(set) var count = 0
    @discardableResult func increment() -> Int { count += 1; return count }
}

final class MutableClock: @unchecked Sendable {
    var current: Date
    init(now: Date) { current = now }
}
