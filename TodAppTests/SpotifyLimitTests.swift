import Foundation
import Testing
@testable import TodApp

/// Spotify's five-account limit, said plainly (`docs/prompt.md`, item 21).
@Suite
struct SpotifyLimitTests {
    @Test
    func spotifysRefusalOfAnUnlistedAccountIsRecognised() {
        let body = Data("Check settings on developer.spotify.com/dashboard, the user may not be registered.".utf8)
        #expect(SpotifyLimit.refusesAccount(status: 403, body: body))
    }

    @Test
    func otherRefusalsAreNotTheLimit() {
        let scope = Data(#"{"error":{"status":403,"message":"Insufficient client scope"}}"#.utf8)
        let registered = Data("the user may not be registered".utf8)
        #expect(!SpotifyLimit.refusesAccount(status: 403, body: scope))
        #expect(!SpotifyLimit.refusesAccount(status: 401, body: registered))
    }

    @Test
    func supabasesWordsForARefusedProfileAreRecognised() {
        #expect(SpotifyLimit.isProfileRefusal("Error getting user profile from external provider"))
        #expect(!SpotifyLimit.isProfileRefusal("Invalid login credentials"))
    }

    @Test
    func theMessageSaysWhyAndWhatStillWorks() {
        let text = PostSongModel.message(for: TodAppError.spotifyNotRegistered)
        #expect(text.contains("Testpersonen"))
        #expect(text.contains("Apple Music"))
    }
}
