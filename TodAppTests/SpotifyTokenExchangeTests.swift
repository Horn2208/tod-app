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

    /// The body is form data, not a query string. A value carrying `+`, `&`
    /// or `=` used to travel unescaped -- `+` arriving as a space, `&` tearing
    /// the body into fields nobody sent.
    @Test
    func awkwardCharactersInAValueSurviveTheBody() async throws {
        let box = RequestBox()
        _ = try await exchange(onRequest: { box.store($0) }).refresh("a+b&grant_type=x/y")

        let fields = formFields(try #require(box.value))
        #expect(fields["refresh_token"] == "a+b&grant_type=x/y")
        #expect(fields["grant_type"] == "refresh_token")
    }

    /// Spotify having a bad minute says nothing about the token. Reporting it
    /// as an authorization failure is what signed people out over it.
    /// `.alphanumerics` counts every Unicode letter, so an "é" used to leave
    /// unencoded. The raw body is what gets checked: decoding it would turn an
    /// unencoded "é" back into the same "é" and prove nothing.
    @Test
    func aNonASCIILetterIsPercentEncoded() async throws {
        let box = RequestBox()
        _ = try await exchange(onRequest: { box.store($0) }).refresh("é")

        let body = String(decoding: try #require(box.value?.httpBody), as: UTF8.self)
        #expect(body.contains("refresh_token=%C3%A9"))
        #expect(!body.contains("é"))
    }

    @Test
    func aServerErrorIsNotAnAuthorizationFailure() async {
        // `.network` is deliberately never equal to anything, not even to
        // another `.network` around the same error (see `TodAppError`), so
        // what gets checked here is the case -- and above all that it is not
        // the one that tells the user to sign in again.
        do {
            _ = try await exchange(status: 500, body: "").refresh("rt-1")
            Issue.record("a 500 must not pass as a refreshed token")
        } catch let error as TodAppError {
            guard case .network = error else {
                Issue.record("a 500 was reported as \(error)")
                return
            }
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test
    func tooManyRequestsIsSaidAsSuch() async {
        await #expect(throws: TodAppError.rateLimited) {
            try await exchange(status: 429, body: "").refresh("rt-1")
        }
    }

    @Test
    func aRejectedExchangeIsAnAuthorizationFailure() async {
        await #expect(throws: TodAppError.authorizationFailed) {
            try await exchange(status: 400, body: #"{"error":"invalid_grant"}"#)
                .exchange(code: "abc123", verifier: "ver-1")
        }
    }
}
