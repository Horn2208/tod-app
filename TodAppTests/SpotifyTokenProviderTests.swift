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
        clock.current = Date(timeIntervalSince1970: 3600)  // exactly at expiry
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
