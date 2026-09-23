import Testing
import WebKit
@testable import TodApp

/// Spotify's embed plays signed out, always. Signed in with Premium it tries
/// the whole song, which needs copy protection an app's web view on the iPhone
/// does not offer -- and then plays nothing at all. Signed out it plays the
/// 30-second excerpt, which works for everyone.
@MainActor
@Suite
struct SpotifyEmbedStoreTests {
    /// A store of its own that keeps nothing: a Spotify login made anywhere
    /// else in the app -- the sign-in sheet runs on the shared store -- never
    /// reaches the embed.
    @Test
    func theEmbedPlaysFromAStoreThatKeepsNoLogin() {
        let configuration = SpotifyEmbedPlayer.makeConfiguration()

        #expect(!configuration.websiteDataStore.isPersistent)
        #expect(configuration.websiteDataStore !== WKWebsiteDataStore.default())
    }
}
