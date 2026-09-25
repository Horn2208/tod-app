import Foundation
import Testing
@testable import TodApp

/// SoundCloud grants no new API keys, but its search page lists the hits in
/// plain HTML for browsers without JavaScript. That list is the search.
@Suite
struct SoundCloudSearchTests {
    private let page = """
    <noscript><ul>
        <li><a href="/search">Search for Everything</a></li>
        <li><a href="/search/sounds">Search for Tracks</a></li>
    </ul>
      <ul>
          <li><h2><a href="/forss/flickermood">Flickermood</a></h2></li>
          <li><h2><a href="/forss-music/forss-flickermood">Flickermood</a></h2></li>
          <li><h2><a href="/someone/sets/a-playlist">A Playlist</a></h2></li>
          <li><h2><a href="/mootleymusic/dj-lu-ne-and-dj-mole-forss">Dj Lu-Ne &amp; Dj Mole - Forss Flickermood</a></h2></li>
      </ul>
    """

    @Test
    func theListedTracksAreTheHits() {
        let hits = SoundCloudSearchPage.hits(in: page)

        #expect(hits.map(\.pageURL.absoluteString) == [
            "https://soundcloud.com/forss/flickermood",
            "https://soundcloud.com/forss-music/forss-flickermood",
            "https://soundcloud.com/mootleymusic/dj-lu-ne-and-dj-mole-forss",
        ])
        #expect(hits.last?.title == "Dj Lu-Ne & Dj Mole - Forss Flickermood")
    }

    @Test
    func aPageWithoutHitsGivesNone() {
        #expect(SoundCloudSearchPage.hits(in: "<html></html>").isEmpty)
    }

    /// Each hit is looked up for its artist, cover and length; one that cannot
    /// be is still offered, under the title the list gave it.
    @Test
    func hitsAreFilledInFromTheirTracks() async throws {
        let page = self.page
        let search = SoundCloudSearchClient(
            performRequest: { request in
                let url = request.url!
                let body: String
                var status = 200
                if url.path.hasPrefix("/search") {
                    body = page
                } else if url.path.hasPrefix("/oembed") {
                    let asked = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                        .queryItems?.first { $0.name == "url" }?.value ?? ""
                    if asked.contains("forss/flickermood") {
                        body = #"{"title":"Flickermood by Forss","author_name":"Forss","thumbnail_url":"https://i1.sndcdn.com/a.jpg"}"#
                    } else {
                        body = ""
                        status = 404
                    }
                } else {
                    body = ""
                }
                return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
            })

        let candidates = try await search.search("flickermood")

        #expect(candidates.count == 3)
        #expect(candidates[0].title == "Flickermood")
        #expect(candidates[0].artist == "Forss")
        #expect(candidates[0].source?.service == .soundcloud)
        #expect(candidates[1].title == "Flickermood")
        #expect(candidates[1].artist == "")
    }
}

@MainActor
@Suite
struct PostSongSoundCloudTests {
    private let hit = TrackCandidate(
        title: "Flickermood", artist: "Forss",
        source: TrackLinkParser.parse("https://soundcloud.com/forss/flickermood"))

    @Test
    func soundCloudHitsComeAsTheirOwnSection() async {
        let hit = self.hit
        let model = PostSongModel(
            provider: FakeMusicProvider(capabilities: .none),
            fallbackSearch: { _ in [] },
            soundCloudSearch: { _ in [hit] },
            debounce: .zero)

        await model.queryChanged("flickermood")

        #expect(await waitUntil { model.soundCloudResults.map(\.id) == [hit.id] })
    }

    /// SoundCloud failing is no error over the main search.
    @Test
    func aFailingSoundCloudSearchIsQuiet() async {
        let model = PostSongModel(
            provider: FakeMusicProvider(capabilities: .none),
            fallbackSearch: { _ in [] },
            soundCloudSearch: { _ in throw TodAppError.searchUnavailable },
            debounce: .zero)

        await model.queryChanged("flickermood")

        #expect(model.errorMessage == nil)
        #expect(model.soundCloudResults.isEmpty)
    }
}
