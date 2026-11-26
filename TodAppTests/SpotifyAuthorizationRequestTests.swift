import Foundation
import Testing
@testable import TodApp

@Suite
struct SpotifyAuthorizationRequestTests {
    private let request = SpotifyAuthorizationRequest(
        clientID: "client-123",
        redirectURI: "todapp://auth/spotify",
        verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk",
        state: "state-abc"
    )

    @Test
    func theURLCarriesEverythingSpotifyDemands() throws {
        let components = try #require(
            URLComponents(url: request.url, resolvingAgainstBaseURL: false)
        )
        let items = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) }
        )

        #expect(components.host == "accounts.spotify.com")
        #expect(components.path == "/authorize")
        #expect(items["response_type"] == "code")
        #expect(items["client_id"] == "client-123")
        #expect(items["redirect_uri"] == "todapp://auth/spotify")
        #expect(items["state"] == "state-abc")
        #expect(items["code_challenge_method"] == "S256")
        #expect(items["code_challenge"] == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    /// Only what is read: `product` (Premium or not) is unreadable without
    /// user-read-private. Playback goes through the Spotify app, so no
    /// playback scopes are asked for.
    @Test
    func theURLAsksForExactlyTheScopesWeNeed() throws {
        let components = try #require(
            URLComponents(url: request.url, resolvingAgainstBaseURL: false)
        )
        let scope = try #require(
            components.queryItems?.first { $0.name == "scope" }?.value
        )

        #expect(Set(scope.split(separator: " ").map(String.init)) == ["user-read-private"])
    }

    @Test
    func readsTheCodeOutOfTheCallback() throws {
        let callback = URL(string: "todapp://auth/spotify?code=abc123&state=state-abc")!

        let code = try SpotifyAuthorizationRequest.code(from: callback, expectedState: "state-abc")

        #expect(code == "abc123")
    }

    /// A callback carrying somebody else's state is the attack this parameter
    /// exists to stop, so it is refused rather than trusted.
    @Test
    func refusesACallbackWhoseStateDoesNotMatch() {
        let callback = URL(string: "todapp://auth/spotify?code=abc123&state=someone-else")!

        #expect(throws: TodAppError.authorizationFailed) {
            try SpotifyAuthorizationRequest.code(from: callback, expectedState: "state-abc")
        }
    }

    @Test
    func refusesACallbackWithoutAState() {
        let callback = URL(string: "todapp://auth/spotify?code=abc123")!

        #expect(throws: TodAppError.authorizationFailed) {
            try SpotifyAuthorizationRequest.code(from: callback, expectedState: "state-abc")
        }
    }

    /// Tapping "Nicht einverstanden" is a decision, not a failure -- the UI
    /// returns to the sign-in screen rather than showing an error.
    @Test
    func aDeniedConsentIsReportedAsACancellation() {
        let callback = URL(string: "todapp://auth/spotify?error=access_denied&state=state-abc")!

        #expect(throws: TodAppError.authorizationCancelled) {
            try SpotifyAuthorizationRequest.code(from: callback, expectedState: "state-abc")
        }
    }

    /// Any error other than access_denied is a server failure or other issue,
    /// not a user choice. State must still match, or the callback is not ours.
    @Test
    func aServerErrorWithCorrectStateIsNotACancellation() {
        let callback = URL(string: "todapp://auth/spotify?error=server_error&state=state-abc")!

        #expect(throws: TodAppError.authorizationFailed) {
            try SpotifyAuthorizationRequest.code(from: callback, expectedState: "state-abc")
        }
    }

    /// A denial from somebody else's authorization flow must not be trusted,
    /// even though it carries an error. The state gate applies to all paths.
    @Test
    func aDeniedConsentWithWrongStateIsRefused() {
        let callback = URL(string: "todapp://auth/spotify?error=access_denied&state=someone-else")!

        #expect(throws: TodAppError.authorizationFailed) {
            try SpotifyAuthorizationRequest.code(from: callback, expectedState: "state-abc")
        }
    }
}
