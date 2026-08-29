import Foundation
import Testing
@testable import TodApp

@Suite
struct SpotifyCredentialsTests {
    /// Bundle cannot be subclassed usefully (no accessible designated init), so
    /// the lookup is injected as a closure instead.
    private func lookup(_ values: [String: String]) -> (String) -> Any? {
        { values[$0] }
    }

    @Test
    func readsCredentialsFromInfoDictionary() throws {
        let credentials = try SpotifyCredentials.from(infoValueForKey: lookup([
            "SpotifyClientID": "id-123", "SpotifyClientSecret": "secret-456"
        ]))

        #expect(credentials.clientID == "id-123")
        #expect(credentials.clientSecret == "secret-456")
    }

    @Test
    func throwsNamedErrorWhenPlaceholderIsStillEmpty() {
        let empty = lookup(["SpotifyClientID": "", "SpotifyClientSecret": ""])

        #expect(throws: TodAppError.missingSpotifyCredentials) {
            try SpotifyCredentials.from(infoValueForKey: empty)
        }
    }

    @Test
    func throwsNamedErrorWhenKeysAreAbsent() {
        #expect(throws: TodAppError.missingSpotifyCredentials) {
            try SpotifyCredentials.from(infoValueForKey: lookup([:]))
        }
    }
}
