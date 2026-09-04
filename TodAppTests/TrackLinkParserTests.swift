import Foundation
import Testing
@testable import TodApp

@Suite
struct TrackLinkParserTests {
    @Test
    func parsesSpotifyWebLink() throws {
        let source = try #require(
            TrackLinkParser.parse("https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT")
        )
        #expect(source.service == .spotify)
        #expect(source.serviceTrackID == "4cOdK2wGLETKBW3PvgPWqT")
    }

    @Test
    func stripsSpotifyTrackingParameter() throws {
        let source = try #require(
            TrackLinkParser.parse("https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT?si=9f2a")
        )
        #expect(source.serviceTrackID == "4cOdK2wGLETKBW3PvgPWqT")
    }

    @Test
    func parsesSpotifyURIScheme() throws {
        let source = try #require(TrackLinkParser.parse("spotify:track:4cOdK2wGLETKBW3PvgPWqT"))
        #expect(source.service == .spotify)
        #expect(source.serviceTrackID == "4cOdK2wGLETKBW3PvgPWqT")
    }

    @Test
    func parsesSoundCloudTrackLink() throws {
        let source = try #require(TrackLinkParser.parse("https://soundcloud.com/artist/some-track"))
        #expect(source.service == .soundcloud)
        #expect(source.serviceTrackID == "https://soundcloud.com/artist/some-track")
    }

    @Test
    func trimsSurroundingWhitespace() throws {
        let source = try #require(
            TrackLinkParser.parse("  https://soundcloud.com/artist/some-track\n")
        )
        #expect(source.service == .soundcloud)
    }

    @Test(arguments: [
        "https://soundcloud.com/artist/sets/some-playlist",  // Playlist, kein Track
        "https://open.spotify.com/album/4cOdK2wGLETKBW3Pvg",  // Album, kein Track
        "https://example.com/track/123",
        "einfach nur text",
        "",
        "https://evilsoundcloud.com/artist/track",  // Foreign host, not real SoundCloud
        "ftp://soundcloud.com/artist/some-track",  // Non-http(s) scheme, SoundCloud host
        "javascript://soundcloud.com/artist/some-track",  // Script scheme disguised as a host
        "ftp://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT",  // Non-http(s) scheme, Spotify host
        "javascript://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT"
    ])
    func rejectsNonTrackInput(_ input: String) {
        #expect(TrackLinkParser.parse(input) == nil)
    }

    @Test
    func rejectsSpotifyTrackWithEncodedCharactersInID() {
        #expect(TrackLinkParser.parse("https://open.spotify.com/track/abc%20def") == nil)
    }

    /// Spotify IDs are base62. `isLetter` and `isNumber` are far wider than that:
    /// they say yes to umlauts, CJK, and Arabic-Indic digits, all of which would
    /// have sailed through into a URL that cannot resolve.
    @Test(arguments: [
        "https://open.spotify.com/track/äöüäöüäöüäöüäöüäöüäöüä",
        "https://open.spotify.com/track/日本語日本語日本語日本語日本語日本語日本",
        "https://open.spotify.com/track/٣٣٣٣٣٣٣٣٣٣٣٣٣٣٣٣٣٣٣٣٣٣",
        "spotify:track:äöüäöüäöüäöüäöüäöüäöüä",
        "https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWq_",
        "https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWq-"
    ])
    func rejectsSpotifyIDsOutsideBase62(_ input: String) {
        #expect(TrackLinkParser.parse(input) == nil)
    }

    /// A pasted http link is a normal thing for a person to do, but carrying the
    /// plain scheme forward would mean the app later fetches the page over it.
    @Test
    func aPastedHTTPSoundCloudLinkIsUpgradedToHTTPS() throws {
        let source = try #require(TrackLinkParser.parse("http://soundcloud.com/artist/some-track"))
        #expect(source.pageURL.scheme == "https")
        #expect(source.serviceTrackID == "https://soundcloud.com/artist/some-track")
    }

    @Test
    func aPastedHTTPSpotifyLinkAlsoEndsUpOnHTTPS() throws {
        let source = try #require(
            TrackLinkParser.parse("http://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT")
        )
        #expect(source.pageURL.scheme == "https")
    }
}
