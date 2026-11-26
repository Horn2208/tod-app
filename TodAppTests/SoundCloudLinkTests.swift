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

/// Sharing from an app often copies a sentence with the link in it; the link
/// is what counts.
@Suite
struct PastedLinkTests {
    @Test
    func theLinkIsTakenOutOfSharedText() {
        #expect(TrackLinkParser.link(in: "Hör dir crashout von IlayTsa auf #SoundCloud an https://on.soundcloud.com/2iQZMwo9IQ8wLY3vf9")
            == "https://on.soundcloud.com/2iQZMwo9IQ8wLY3vf9")
        #expect(TrackLinkParser.link(in: "https://open.spotify.com/track/abc") == "https://open.spotify.com/track/abc")
        #expect(TrackLinkParser.link(in: "spotify:track:51KP8yo3FnpKJtrQIsriu4") == "spotify:track:51KP8yo3FnpKJtrQIsriu4")
        #expect(TrackLinkParser.link(in: "kein Link hier") == "kein Link hier")
    }
}

/// Some uploaders forbid embedding ("embeddable_by": "me"): oEmbed answers 403.
/// The track can still be posted, from what its public page says.
@Suite
struct SoundCloudNoEmbedTests {
    private let source = TrackLinkParser.parse("https://soundcloud.com/distributor-979395764/souly-versace-python-remix")!
    private let page = """
    <meta property="og:title" content="SOULY - VERSACE PYTHON REMIX (feat. Riff Raff)">
    <meta property="og:image" content="https://i1.sndcdn.com/artworks-s6o6YVbbcyIe2GxF-LXAF6Q-t500x500.jpg">
    <meta itemprop="duration" content="PT00H03M24S" />
    <div itemprop="byArtist" itemscope itemtype="http://schema.org/MusicGroup"><meta itemprop="name" content="distributor" />
    """

    private func respond(_ body: String, to url: URL, status: Int = 200) -> (Data, URLResponse) {
        (Data(body.utf8), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    @Test
    func aRefusedEmbedIsPostedFromThePage() async throws {
        let page = self.page
        let client = SoundCloudOEmbedClient(performRequest: { request in
            let url = request.url!
            if url.path.hasPrefix("/oembed") { return self.respond("", to: url, status: 403) }
            return self.respond(page, to: url)
        })

        let candidate = try await client.candidate(for: source)

        #expect(candidate.title == "VERSACE PYTHON REMIX (feat. Riff Raff)")
        #expect(candidate.artist == "SOULY")
        #expect(candidate.durationSeconds == 204)
        #expect(candidate.source?.artworkURL?.lastPathComponent == "artworks-s6o6YVbbcyIe2GxF-LXAF6Q-t500x500.jpg")
    }

    /// Without "Artist - Title" the uploader's name is the artist.
    @Test
    func withoutADashTheUploaderIsTheArtist() throws {
        let details = SoundCloudTrackPage.details(from: """
        <meta property="og:title" content="Flickermood">
        <meta itemprop="name" content="Forss" />
        """)
        let named = try #require(SoundCloudTrackPage.titleAndArtist(details))
        #expect(named.title == "Flickermood")
        #expect(named.artist == "Forss")
    }

    @Test
    func neitherPageNorOEmbedIsUnavailable() async {
        let client = SoundCloudOEmbedClient(performRequest: { request in
            self.respond("", to: request.url!, status: request.url!.path.hasPrefix("/oembed") ? 403 : 404)
        })
        await #expect(throws: TodAppError.trackUnavailable) {
            try await client.candidate(for: self.source)
        }
    }
}
