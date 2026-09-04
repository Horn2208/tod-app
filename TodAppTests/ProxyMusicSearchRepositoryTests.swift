import Foundation
import Testing
@testable import TodApp

/// The proxy hands Spotify's own search body straight through, so the client
/// keeps one mapper and one recorded fixture instead of a second wire format.
@Suite
struct ProxyMusicSearchRepositoryTests {
    private let body = Data("""
    {"tracks":{"items":[
      {"id":"4cOdK2wGLETKBW3PvgPWqT","name":"As It Was",
       "artists":[{"name":"Harry Styles"}],
       "external_urls":{"spotify":"https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT"},
       "album":{"images":[{"url":"https://i.scdn.co/image/medium","width":300}]}}
    ]}}
    """.utf8)

    private func repository(
        status: Int = 200,
        body: Data? = nil,
        onRequest: (@Sendable (URLRequest) -> Void)? = nil
    ) -> ProxyMusicSearchRepository {
        let payload = body ?? self.body
        return ProxyMusicSearchRepository(
            baseURL: URL(string: "https://proxy.example.com")!,
            performRequest: { request in
                onRequest?(request)
                return (
                    payload,
                    HTTPURLResponse(
                        url: request.url!, statusCode: status,
                        httpVersion: nil, headerFields: nil
                    )!
                )
            }
        )
    }

    @Test
    func aBlankQueryReturnsNothingWithoutCallingTheProxy() async throws {
        let repo = ProxyMusicSearchRepository(
            baseURL: URL(string: "https://proxy.example.com")!,
            performRequest: { _ in
                Issue.record("must not call the proxy for a blank query")
                return (Data(), HTTPURLResponse())
            }
        )

        #expect(try await repo.searchTracks(matching: "   ").isEmpty)
    }

    @Test
    func mapsTheProxyBodyWithTheSameMapperAsDirectSpotify() async throws {
        let results = try await repository().searchTracks(matching: "as it was")

        #expect(results.count == 1)
        #expect(results[0].title == "As It Was")
        #expect(results[0].source.artworkURL?.absoluteString == "https://i.scdn.co/image/medium")
    }

    @Test
    func asksTheProxyForSearchWithTheQueryAttached() async throws {
        let seen = RequestBox()
        _ = try await repository(onRequest: { seen.store($0) }).searchTracks(matching: "as it was")

        let request = try #require(seen.value)
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.host == "proxy.example.com")
        #expect(components.path == "/search")
        #expect(components.queryItems?.first { $0.name == "q" }?.value == "as it was")
    }

    /// The whole point of the proxy: nothing secret travels with the request.
    @Test
    func sendsNoAuthorizationHeader() async throws {
        let seen = RequestBox()
        _ = try await repository(onRequest: { seen.store($0) }).searchTracks(matching: "x")

        #expect(seen.value?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test
    func tooManyRequestsIsReportedAsRateLimited() async {
        await #expect(throws: TodAppError.rateLimited) {
            try await repository(status: 429).searchTracks(matching: "x")
        }
    }

    /// A rejected proxy call is the server's credentials problem, not the
    /// user's -- pointing them at Secrets.xcconfig would be nonsense in an app
    /// that no longer ships one.
    @Test(arguments: [401, 403, 500, 502, 503])
    func aBrokenProxyIsReportedAsSearchUnavailable(_ status: Int) async {
        await #expect(throws: TodAppError.searchUnavailable) {
            try await repository(status: status).searchTracks(matching: "x")
        }
    }

    @Test
    func anUnexpectedStatusIsReportedAsTrackUnavailable() async {
        await #expect(throws: TodAppError.trackUnavailable) {
            try await repository(status: 418).searchTracks(matching: "x")
        }
    }
}

/// Captures the request the repository built, across the Sendable boundary the
/// injected closure imposes.
private final class RequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: URLRequest?

    var value: URLRequest? {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    func store(_ request: URLRequest) {
        lock.lock(); defer { lock.unlock() }
        stored = request
    }
}
