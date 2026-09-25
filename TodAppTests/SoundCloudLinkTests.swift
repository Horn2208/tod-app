import Foundation
import Testing
@testable import TodApp

/// SoundCloud links as people actually paste them: the app's share link, and
/// a track whose page says more than oEmbed.
@Suite
struct SoundCloudLinkTests {
    private func respond(_ body: String, to url: URL, status: Int = 200) -> (Data, URLResponse) {
        (Data(body.utf8), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    /// The SoundCloud app shares `on.soundcloud.com/…`, which only redirects
    /// to the track.
    @Test
    func aShareLinkIsRecognised() {
        #expect(TrackLinkParser.soundCloudShareLink("https://on.soundcloud.com/7WkUVqDdYt4B6GaT7")
            == URL(string: "https://on.soundcloud.com/7WkUVqDdYt4B6GaT7"))
        #expect(TrackLinkParser.soundCloudShareLink("https://soundcloud.com/forss/flickermood") == nil)
        #expect(TrackLinkParser.soundCloudShareLink("https://on.soundcloud.com/") == nil)
    }

    /// Following the share link lands on the track's page -- where the
    /// redirect ends is the track.
    @Test
    func aShareLinkResolvesToItsTrack() async throws {
        let track = URL(string: "https://soundcloud.com/forss/flickermood?utm_source=clipboard")!
        let client = SoundCloudOEmbedClient(performRequest: { _ in self.respond("", to: track) })

        let resolved = try await client.resolve(shareLink: URL(string: "https://on.soundcloud.com/abc")!)

        #expect(TrackLinkParser.parse(resolved.absoluteString)?.pageURL
            == URL(string: "https://soundcloud.com/forss/flickermood"))
    }

    /// oEmbed's title carries " by <artist>"; the song's name does not.
    @Test
    func theArtistComesOffTheTitle() throws {
        let source = TrackLinkParser.parse("https://soundcloud.com/forss/flickermood")!
        let data = Data(#"{"title":"Flickermood by Forss","author_name":"Forss"}"#.utf8)

        let candidate = try SoundCloudOEmbedMapper.candidate(from: data, source: source)

        #expect(candidate.title == "Flickermood")
        #expect(candidate.artist == "Forss")
    }

    /// The track's page names its length (and its title, cleanly).
    @Test
    func thePageGivesTheLength() {
        let details = SoundCloudTrackPage.details(from: """
        <meta property="og:title" content="Flickermood">
        <meta itemprop="duration" content="PT00H03M33S" />
        """)

        #expect(details.title == "Flickermood")
        #expect(details.durationSeconds == 213)
    }

    @Test
    func aLinkCandidateGetsItsLength() async throws {
        let source = TrackLinkParser.parse("https://soundcloud.com/forss/flickermood")!
        let client = SoundCloudOEmbedClient(performRequest: { request in
            let url = request.url!
            if url.path.hasPrefix("/oembed") {
                return self.respond(#"{"title":"Flickermood by Forss","author_name":"Forss"}"#, to: url)
            }
            return self.respond(#"<meta itemprop="duration" content="PT00H03M33S" />"#, to: url)
        })

        let candidate = try await client.candidate(for: source)

        #expect(candidate.title == "Flickermood")
        #expect(candidate.durationSeconds == 213)
    }
}
