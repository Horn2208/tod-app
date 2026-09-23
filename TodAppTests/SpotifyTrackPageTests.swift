import Foundation
import Testing
@testable import TodApp

/// A pasted Spotify link's oEmbed names the title only. The public track page
/// names the artist and the length too -- what Apple's catalog needs to find
/// the same recording.
@Suite
struct SpotifyTrackPageTests {
    private let source = TrackSource(
        service: .spotify,
        serviceTrackID: "51KP8yo3FnpKJtrQIsriu4",
        pageURL: URL(string: "https://open.spotify.com/track/51KP8yo3FnpKJtrQIsriu4")!,
        artworkURL: nil
    )

    /// The meta tags as Spotify served them for "Azzlack Versace".
    private let page = """
    <meta property="og:title" content="Azzlack Versace"/>
    <meta name="music:duration" content="240"/>
    <meta name="music:musician" content="https://open.spotify.com/artist/3Vnl7pKDxagUgRJ3NMtEcE"/>
    <meta name="music:musician_description" content="Soufian, Haftbefehl"/>
    """

    @Test
    func readsArtistAndLength() {
        let details = SpotifyTrackPage.details(from: page)

        #expect(details.artist == "Soufian, Haftbefehl")
        #expect(details.durationSeconds == 240)
    }

    @Test
    func decodesEscapedCharacters() {
        let details = SpotifyTrackPage.details(from: """
        <meta name="music:musician_description" content="Simon &amp; Garfunkel, Guns N&#x27; Roses"/>
        """)

        #expect(details.artist == "Simon & Garfunkel, Guns N' Roses")
        #expect(details.durationSeconds == nil)
    }

    @Test
    func aPageWithoutTheTagsGivesNothing() {
        let details = SpotifyTrackPage.details(from: "<html><head></head></html>")

        #expect(details.artist == nil)
        #expect(details.durationSeconds == nil)
    }

    private func respond(_ body: String, to url: URL, status: Int = 200) -> (Data, URLResponse) {
        (Data(body.utf8), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    /// The link's candidate carries what the page says, beside oEmbed's title
    /// and cover.
    @Test
    func aLinkCandidateGetsArtistAndLengthFromThePage() async throws {
        let page = self.page
        let client = SpotifyOEmbedClient(performRequest: { request in
            let url = request.url!
            if url.path.hasPrefix("/oembed") {
                return self.respond(#"{"title":"Azzlack Versace","thumbnail_url":"https://i.scdn.co/image/x"}"#, to: url)
            }
            return self.respond(page, to: url)
        })

        let candidate = try await client.candidate(for: source)

        #expect(candidate.title == "Azzlack Versace")
        #expect(candidate.artist == "Soufian, Haftbefehl")
        #expect(candidate.durationSeconds == 240)
        #expect(candidate.source.artworkURL?.absoluteString == "https://i.scdn.co/image/x")
    }

    /// The page is a bonus: when it fails, the link still resolves as before.
    @Test
    func aFailingPageLeavesTheOEmbedResult() async throws {
        let client = SpotifyOEmbedClient(performRequest: { request in
            let url = request.url!
            if url.path.hasPrefix("/oembed") {
                return self.respond(#"{"title":"Azzlack Versace"}"#, to: url)
            }
            throw URLError(.notConnectedToInternet)
        })

        let candidate = try await client.candidate(for: source)

        #expect(candidate.title == "Azzlack Versace")
        #expect(candidate.artist == "")
        #expect(candidate.durationSeconds == nil)
    }
}
