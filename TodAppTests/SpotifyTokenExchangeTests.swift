import Foundation
import Testing
@testable import TodApp

@Suite
struct SpotifyTokenExchangeTests {
    private func exchange(
        status: Int = 200,
        body: String = #"{"access_token":"at","refresh_token":"rt","expires_in":3600}"#,
        onRequest: (@Sendable (URLRequest) -> Void)? = nil
    ) -> SpotifyTokenExchange {
        SpotifyTokenExchange(
            clientID: "client-123",
            redirectURI: "todapp://auth/spotify",
            performRequest: { request in
                onRequest?(request)
                return (
                    Data(body.utf8),
                    HTTPURLResponse(url: request.url!, statusCode: status,
                                    httpVersion: nil, headerFields: nil)!
                )
            },
            now: { Date(timeIntervalSince1970: 0) }
        )
    }

    private func formFields(_ request: URLRequest) -> [String: String] {
        let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        return Dictionary(
            body.split(separator: "&").compactMap { pair -> (String, String)? in
                let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return nil }
                return (parts[0], parts[1].removingPercentEncoding ?? parts[1])
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    @Test
    func exchangingACodeSendsTheVerifierAndNoSecret() async throws {
        let box = RequestBox()
        _ = try await exchange(onRequest: { box.store($0) })
            .exchange(code: "abc123", verifier: "ver-1")

        let request = try #require(box.value)
        let fields = formFields(request)
        #expect(fields["grant_type"] == "authorization_code")
        #expect(fields["code"] == "abc123")
        #expect(fields["code_verifier"] == "ver-1")
        #expect(fields["client_id"] == "client-123")
        // The whole point of PKCE: nothing secret travels.
        #expect(fields["client_secret"] == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test
    func readsTheTokensAndTheirExpiry() async throws {
        let tokens = try await exchange().exchange(code: "abc123", verifier: "ver-1")

        #expect(tokens.accessToken == "at")
        #expect(tokens.refreshToken == "rt")
        #expect(tokens.expiresAt == Date(timeIntervalSince1970: 3570))  // 3600 - margin
    }

    @Test
    func refreshingSendsTheRefreshTokenAndNoSecret() async throws {
        let box = RequestBox()
        _ = try await exchange(onRequest: { box.store($0) }).refresh("rt-1")

        let fields = formFields(try #require(box.value))
        #expect(fields["grant_type"] == "refresh_token")
        #expect(fields["refresh_token"] == "rt-1")
        #expect(fields["client_id"] == "client-123")
        #expect(fields["client_secret"] == nil)
    }

    /// Spotify may answer a refresh without a new refresh token, and the old
    /// one keeps working. Overwriting it with nil would sign the user out.
    @Test
    func aRefreshWithoutANewRefreshTokenKeepsTheOldOne() async throws {
        let tokens = try await exchange(body: #"{"access_token":"at2","expires_in":3600}"#)
            .refresh("rt-1")

        #expect(tokens.accessToken == "at2")
        #expect(tokens.refreshToken == nil)
    }

    @Test
    func aRejectedExchangeIsAnAuthorizationFailure() async {
        await #expect(throws: TodAppError.authorizationFailed) {
            try await exchange(status: 400, body: #"{"error":"invalid_grant"}"#)
                .exchange(code: "abc123", verifier: "ver-1")
        }
    }
}
