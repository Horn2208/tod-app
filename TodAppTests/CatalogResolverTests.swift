import Foundation
import Testing
@testable import TodApp

/// A catalog that answers from memory and counts what it was asked.
actor FakeCatalog: MusicCatalog {
    private let hits: [CatalogSong]
    private let byID: [String: CatalogSong]
    private let byISRC: [String: CatalogSong]
    private var failuresLeft: Int
    private(set) var searches = 0
    private(set) var lookups = 0
    private(set) var isrcLookups = 0

    init(
        hits: [CatalogSong] = [],
        byID: [String: CatalogSong] = [:],
        byISRC: [String: CatalogSong] = [:],
        failing: Int = 0
    ) {
        self.hits = hits
        self.byID = byID
        self.byISRC = byISRC
        self.failuresLeft = failing
    }

    func search(title: String, artist: String) async throws -> [CatalogSong] {
        searches += 1
        if failuresLeft > 0 {
            failuresLeft -= 1
            throw TodAppError.searchUnavailable
        }
        return hits
    }

    func song(id: String) async throws -> CatalogSong? {
        lookups += 1
        return byID[id]
    }

    func song(isrc: String) async throws -> CatalogSong? {
        isrcLookups += 1
        return byISRC[isrc]
    }
}

@MainActor
@Suite
struct CatalogResolverTests {
    private let blindingLights = CatalogSong(
        id: "1499378607", title: "Blinding Lights", artist: "The Weeknd", durationSeconds: 200)
    private let source = TrackSource(
        service: .spotify, serviceTrackID: "0VjIjW4GlUZAMYd2vXMi3b",
        pageURL: URL(string: "https://open.spotify.com/track/0VjIjW4GlUZAMYd2vXMi3b")!)

    private var key: String {
        CatalogKey.of(source: source, title: "Blinding Lights", artist: "The Weeknd")
    }

    private func resolve(_ resolver: CatalogResolver, knownID: String? = nil) async -> CatalogResolver.Outcome {
        await resolver.resolve(
            key: key, title: "Blinding Lights", artist: "The Weeknd",
            durationSeconds: 200, knownID: knownID)
    }

    @Test
    func aMatchIsFoundAndAskedForOnlyOnce() async {
        let catalog = FakeCatalog(hits: [blindingLights])
        let resolver = CatalogResolver(catalog: catalog)

        #expect(await resolve(resolver) == .found(blindingLights))
        _ = await resolve(resolver)

        #expect(await catalog.searches == 1)
        #expect(resolver.settled(for: key) == .found(blindingLights))
    }

    /// "Not in the catalog" is a verdict about the song. It is kept, so the
    /// embed fallback does not cost a search on every open.
    @Test
    func noMatchIsRememberedToo() async {
        let catalog = FakeCatalog(hits: [])
        let resolver = CatalogResolver(catalog: catalog)

        #expect(await resolve(resolver) == .notInCatalog)
        _ = await resolve(resolver)

        #expect(await catalog.searches == 1)
    }

    /// A failed request says nothing about the song. Remembering it would
    /// send the song to the fallback for as long as the app runs.
    @Test
    func aFailedRequestIsNotRemembered() async {
        let catalog = FakeCatalog(hits: [blindingLights], failing: 1)
        let resolver = CatalogResolver(catalog: catalog)

        #expect(await resolve(resolver) == .notInCatalog)
        #expect(resolver.settled(for: key) == nil)
        #expect(await resolve(resolver) == .found(blindingLights))
    }

    @Test
    func aStoredIDIsLookedUpNotSearched() async {
        let catalog = FakeCatalog(byID: ["1499378607": blindingLights])
        let resolver = CatalogResolver(catalog: catalog)

        #expect(await resolve(resolver, knownID: "1499378607") == .found(blindingLights))
        #expect(await catalog.searches == 0)
    }

    /// A catalog can drop a song. The stored id then leads nowhere, and the
    /// search runs as if there had been none.
    @Test
    func aStoredIDTheCatalogLostFallsBackToSearch() async {
        let catalog = FakeCatalog(hits: [blindingLights])
        let resolver = CatalogResolver(catalog: catalog)

        #expect(await resolve(resolver, knownID: "gone") == .found(blindingLights))
        #expect(await catalog.lookups == 1)
        #expect(await catalog.searches == 1)
    }
}

@Suite
struct CatalogKeyTests {
    private func source(_ id: String) -> TrackSource {
        TrackSource(
            service: .spotify, serviceTrackID: id,
            pageURL: URL(string: "https://open.spotify.com/track/\(id)")!)
    }

    @Test
    func twoLinksAreTwoTracks() {
        #expect(CatalogKey.of(source: source("a"), title: "X", artist: "Y")
                != CatalogKey.of(source: source("b"), title: "X", artist: "Y"))
    }

    /// A link is the identity when there is one: the same track posted with a
    /// sloppier title is still that track.
    @Test
    func theLinkWinsOverTheTitle() {
        #expect(CatalogKey.of(source: source("a"), title: "X", artist: "Y")
                == CatalogKey.of(source: source("a"), title: "ganz anders", artist: "Z"))
    }

    /// Without a link, title and artist are all anyone has -- so two posts of
    /// the same song share the one answer the catalog gave.
    @Test
    func withoutALinkTheSongIsItsTitleAndArtist() {
        #expect(CatalogKey.of(source: nil, title: "Redbone", artist: "Childish Gambino")
                == CatalogKey.of(source: nil, title: "REDBONE", artist: "Childish Gambino"))
        #expect(CatalogKey.of(source: nil, title: "Redbone", artist: "Childish Gambino")
                != CatalogKey.of(source: nil, title: "Redbone", artist: "Someone Else"))
    }
}

@MainActor
@Suite
struct CatalogResolverISRCTests {
    private let blindingLights = CatalogSong(
        id: "1499378607", title: "Blinding Lights", artist: "The Weeknd", durationSeconds: 200)

    /// The ISRC names the recording; a title and an artist only describe it.
    /// When the catalog knows the number, the text search is never asked.
    @Test
    func anISRCIsAskedBeforeTheTextSearch() async {
        let catalog = FakeCatalog(hits: [], byISRC: ["ISRC-1": blindingLights])
        let resolver = CatalogResolver(catalog: catalog)

        let outcome = await resolver.resolve(
            key: "spotify:a", title: "Blinding Lights", artist: "The Weeknd",
            durationSeconds: 200, knownID: nil, isrc: "ISRC-1")

        #expect(outcome == .found(blindingLights))
        #expect(await catalog.searches == 0)
    }

    /// A catalog can file a radio edit under the album cut's number. A length
    /// that contradicts the post sends the lookup on to the text search.
    @Test
    func anISRCWithTheWrongLengthFallsThroughToTheSearch() async {
        let edit = CatalogSong(id: "9", title: "Blinding Lights", artist: "The Weeknd", durationSeconds: 170)
        let catalog = FakeCatalog(hits: [blindingLights], byISRC: ["ISRC-1": edit])
        let resolver = CatalogResolver(catalog: catalog)

        let outcome = await resolver.resolve(
            key: "spotify:b", title: "Blinding Lights", artist: "The Weeknd",
            durationSeconds: 200, knownID: nil, isrc: "ISRC-1")

        #expect(outcome == .found(blindingLights))
        #expect(await catalog.searches == 1)
    }

    /// A remembered "not in the catalog" came from a text search. An ISRC is
    /// better evidence than that, so it still gets asked.
    @Test
    func anISRCIsAskedEvenAfterASearchFoundNothing() async {
        let catalog = FakeCatalog(hits: [], byISRC: ["ISRC-1": blindingLights])
        let resolver = CatalogResolver(catalog: catalog)

        let first = await resolver.resolve(
            key: "spotify:c", title: "Blinding Lights", artist: "The Weeknd",
            durationSeconds: 200, knownID: nil)
        let second = await resolver.resolve(
            key: "spotify:c", title: "Blinding Lights", artist: "The Weeknd",
            durationSeconds: 200, knownID: nil, isrc: "ISRC-1")

        #expect(first == .notInCatalog)
        #expect(second == .found(blindingLights))
    }
}

@MainActor
@Suite
struct CatalogResolverStoredIDTests {
    /// A search that found nothing is remembered under its key. A later post
    /// of the same track, carrying the id matched when it went up, must still
    /// get that match instead of the search's old "nothing".
    @Test
    func aStoredIDStillCountsAfterASearchFoundNothing() async {
        let song = CatalogSong(
            id: "1499378607", title: "Blinding Lights", artist: "The Weeknd", durationSeconds: 200)
        let resolver = CatalogResolver(catalog: FakeCatalog(hits: [], byID: ["1499378607": song]))

        let first = await resolver.resolve(
            key: "spotify:x", title: "Blinding Lights", artist: "The Weeknd",
            durationSeconds: 200, knownID: nil)
        let second = await resolver.resolve(
            key: "spotify:x", title: "Blinding Lights", artist: "The Weeknd",
            durationSeconds: 200, knownID: "1499378607")

        #expect(first == .notInCatalog)
        #expect(second == .found(song))
    }
}

@MainActor
@Suite
struct PostCarriesCatalogIDsTests {
    @Test
    func aPostKeepsTheISRCAndTheAppleMusicMatch() async throws {
        let repo = InMemoryRepository()
        let store = AppStore(
            groupRepo: repo, submissionRepo: repo, voteRepo: repo,
            chatRepo: repo, battleRepo: repo,
            provider: FakeMusicProvider(capabilities: .none),
            reminders: RecordingReminders())
        await store.loadGroups()
        let candidate = TrackCandidate(
            title: "Blinding Lights", artist: "The Weeknd",
            source: TrackSource(
                service: .spotify, serviceTrackID: "posted",
                pageURL: URL(string: "https://open.spotify.com/track/posted")!),
            durationSeconds: 200, isrc: "USUG11904206")

        await store.post(candidate: candidate, appleMusicID: "1499378607")

        let posted = try #require(store.groups.flatMap(\.submissions)
            .first { $0.source?.serviceTrackID == "posted" })
        #expect(posted.isrc == "USUG11904206")
        #expect(posted.appleMusicID == "1499378607")
    }

    /// Spotify's search carries the ISRC under `external_ids`; a payload
    /// without the field still decodes.
    @Test
    func spotifysSearchHandsOverTheISRC() throws {
        let json = """
        {"tracks":{"items":[
        {"id":"a","name":"A","artists":[{"name":"X"}],"external_urls":{"spotify":"https://open.spotify.com/track/a"},
         "album":{"images":[]},"duration_ms":200000,"external_ids":{"isrc":"USUG11904206"}},
        {"id":"b","name":"B","artists":[{"name":"Y"}],"external_urls":{"spotify":"https://open.spotify.com/track/b"},
         "album":{"images":[]},"duration_ms":100000}
        ]}}
        """
        let candidates = try SpotifyResponseMapper.candidates(from: Data(json.utf8))

        #expect(candidates.map(\.isrc) == ["USUG11904206", nil])
    }
}
