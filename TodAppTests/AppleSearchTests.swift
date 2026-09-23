import Foundation
import Testing
@testable import TodApp

/// Without a Spotify connection, the post sheet searches Apple's catalog: no
/// account needed, and the song plays through Apple -- whole with a
/// subscription, the preview without. Spotify allows only five testers, so
/// this is how everyone else finds songs.
@MainActor
@Suite
struct AppleSearchTests {
    private let song = CatalogSong(
        id: "1499378607", title: "Blinding Lights", artist: "The Weeknd", durationSeconds: 200,
        previewURL: URL(string: "https://audio-ssl.itunes.apple.com/x.m4a"),
        pageURL: URL(string: "https://music.apple.com/de/album/x?i=1499378607"),
        artworkURL: URL(string: "https://is1-ssl.mzstatic.com/image/thumb/x/100x100bb.jpg"))

    /// An Apple hit has no service link: it is the post without one that the
    /// app has always known, with its catalog id, cover and length.
    @Test
    func anAppleSongBecomesACandidateWithoutALink() {
        let candidate = TrackCandidate(appleSong: song)

        #expect(candidate.source == nil)
        #expect(candidate.title == "Blinding Lights")
        #expect(candidate.artist == "The Weeknd")
        #expect(candidate.appleMusicID == "1499378607")
        // Apple hands out 100 pixels; the post's cover is shown far larger.
        #expect(candidate.artworkURL?.lastPathComponent == "600x600bb.jpg")
        #expect(candidate.durationSeconds == 200)
        #expect(candidate.id == "apple:1499378607")
    }

    /// Nobody signed in to Spotify: the search goes to Apple.
    @Test
    func withoutSpotifyTheSearchAsksApple() async {
        let song = self.song
        let model = PostSongModel(
            provider: FakeMusicProvider(capabilities: .none),
            fallbackSearch: { _ in [TrackCandidate(appleSong: song)] },
            debounce: .zero)

        await model.queryChanged("blinding lights")

        #expect(model.results.map(\.id) == ["apple:1499378607"])
        #expect(model.errorMessage == nil)
    }

    /// With Spotify connected, the search stays Spotify's.
    @Test
    func withSpotifyTheSearchStaysSpotifys() async throws {
        let spotifyHit = TrackCandidate(
            title: "Blinding Lights", artist: "The Weeknd",
            source: TrackSource(
                service: .spotify, serviceTrackID: "0VjIjW4GlUZAMYd2vXMi3b",
                pageURL: URL(string: "https://open.spotify.com/track/0VjIjW4GlUZAMYd2vXMi3b")!))
        let provider = FakeMusicProvider(
            capabilities: MusicProviderCapabilities(
                canSearch: true, canPlayFullTracks: false, canStartAtPosition: false, playsInsideTheApp: false),
            search: { _ in [spotifyHit] })
        try await provider.authorize()
        let model = PostSongModel(
            provider: provider, fallbackSearch: { _ in Issue.record("Apple asked"); return [] }, debounce: .zero)

        await model.queryChanged("blinding lights")

        #expect(model.results.map(\.id) == [spotifyHit.id])
    }

    /// Connected, but Spotify refuses: an account outside the five testers
    /// Spotify's development mode lets through. Apple answers instead.
    @Test
    func aSpotifyRefusalFallsBackToApple() async throws {
        let song = self.song
        let provider = FakeMusicProvider(
            capabilities: MusicProviderCapabilities(
                canSearch: true, canPlayFullTracks: false, canStartAtPosition: false, playsInsideTheApp: false),
            search: { _ in throw TodAppError.authorizationFailed })
        try await provider.authorize()
        let model = PostSongModel(
            provider: provider, fallbackSearch: { _ in [TrackCandidate(appleSong: song)] }, debounce: .zero)

        await model.queryChanged("blinding lights")

        #expect(model.results.map(\.id) == ["apple:1499378607"])
        #expect(model.errorMessage == nil)
    }

    @Test
    func aFailingAppleSearchSaysSo() async {
        let model = PostSongModel(
            provider: FakeMusicProvider(capabilities: .none),
            fallbackSearch: { _ in throw TodAppError.searchUnavailable },
            debounce: .zero)

        await model.queryChanged("blinding lights")

        #expect(model.results.isEmpty)
        #expect(model.errorMessage == PostSongModel.message(for: TodAppError.searchUnavailable))
    }

    /// Posted, it keeps the catalog id -- the player looks it up by that
    /// instead of guessing from the title -- and its cover and length.
    @Test
    func anAppleSongPostsWithItsCatalogIDCoverAndLength() async throws {
        let repo = InMemoryRepository()
        let store = AppStore(
            groupRepo: repo, submissionRepo: repo, voteRepo: repo,
            chatRepo: repo, battleRepo: repo,
            provider: FakeMusicProvider(capabilities: .none),
            reminders: RecordingReminders())
        await store.loadGroups()

        await store.post(candidate: TrackCandidate(appleSong: song))

        let posted = try #require(store.groups.flatMap(\.submissions).first { $0.appleMusicID == "1499378607" })
        #expect(posted.source == nil)
        #expect(posted.coverURL?.lastPathComponent == "600x600bb.jpg")
        #expect(posted.durationSeconds == 200)
        #expect(posted.coverColorHex == CoverColor.hex(forTrack: "Blinding Lights|The Weeknd"))
    }

    /// Apple's search answers songs for a free-text term.
    @Test
    func theCatalogSearchesByTerm() async throws {
        let catalog = ITunesCatalog(country: "de", fetch: { request in
            let url = request.url!
            #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                .first { $0.name == "term" }?.value == "blinding lights")
            let body = #"{"results":[{"kind":"song","trackId":1499378607,"trackName":"Blinding Lights","artistName":"The Weeknd","trackTimeMillis":200040}]}"#
            return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })

        let songs = try await catalog.search(term: "blinding lights")

        #expect(songs.map(\.id) == ["1499378607"])
        #expect(songs.first?.durationSeconds == 200)
    }
}
