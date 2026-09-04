import Foundation
import Testing
@testable import TodApp

struct MockMusicSearchRepository: MusicSearchRepository {
    var candidates: [TrackCandidate] = []
    var error: TodAppError?
    func searchTracks(matching query: String) async throws -> [TrackCandidate] {
        if let error { throw error }
        return candidates
    }
}

/// Lets a test hold a `searchTracks` call open until it explicitly releases
/// it, and lets the test know once the call has actually started waiting --
/// so two overlapping `queryChanged` calls can be driven into a real race
/// instead of hoping timing works out.
actor SearchGate {
    private var startedQueries: Set<String> = []
    private var startContinuations: [String: CheckedContinuation<Void, Never>] = [:]
    private var releasedQueries: Set<String> = []
    private var releaseContinuations: [String: CheckedContinuation<Void, Never>] = [:]

    func markStarted(_ query: String) {
        startedQueries.insert(query)
        startContinuations.removeValue(forKey: query)?.resume()
    }

    func waitUntilStarted(_ query: String) async {
        if startedQueries.contains(query) { return }
        await withCheckedContinuation { startContinuations[query] = $0 }
    }

    func waitForRelease(_ query: String) async {
        if releasedQueries.contains(query) { return }
        await withCheckedContinuation { releaseContinuations[query] = $0 }
    }

    func release(_ query: String) {
        releasedQueries.insert(query)
        releaseContinuations.removeValue(forKey: query)?.resume()
    }
}

struct GatedMusicSearchRepository: MusicSearchRepository {
    let gate: SearchGate
    let resultsByQuery: [String: [TrackCandidate]]

    func searchTracks(matching query: String) async throws -> [TrackCandidate] {
        await gate.markStarted(query)
        await gate.waitForRelease(query)
        return resultsByQuery[query] ?? []
    }
}

@Suite
@MainActor
struct PostSongModelTests {
    private func candidate(_ id: String) -> TrackCandidate {
        TrackCandidate(
            title: "Genesis", artist: "Justice",
            source: TrackSource(
                service: .spotify, serviceTrackID: id,
                pageURL: URL(string: "https://open.spotify.com/track/\(id)")!, artworkURL: nil
            )
        )
    }

    @Test
    func searchPopulatesResults() async {
        let model = PostSongModel(
            search: MockMusicSearchRepository(candidates: [candidate("a")]),
            debounce: .zero
        )

        await model.queryChanged("justice")

        #expect(model.results.map(\.id) == ["spotify:a"])
        #expect(model.isSearching == false)
    }

    @Test
    func missingCredentialsProduceAnActionableMessage() async {
        let model = PostSongModel(
            search: MockMusicSearchRepository(error: .missingSpotifyCredentials),
            debounce: .zero
        )

        await model.queryChanged("justice")

        #expect(model.results.isEmpty)
        #expect(model.errorMessage?.contains("Secrets.xcconfig") == true)
    }

    @Test
    func rateLimitIsReportedSeparatelyFromOtherFailures() async {
        let model = PostSongModel(
            search: MockMusicSearchRepository(error: .rateLimited), debounce: .zero
        )

        await model.queryChanged("justice")

        #expect(model.errorMessage?.contains("zu viele") == true)
    }

    @Test
    func clearingTheQueryClearsResultsAndError() async {
        let model = PostSongModel(
            search: MockMusicSearchRepository(candidates: [candidate("a")]), debounce: .zero
        )
        await model.queryChanged("justice")

        await model.queryChanged("")

        #expect(model.results.isEmpty)
        #expect(model.errorMessage == nil)
    }

    /// Pins the fix for the race the brief's dead `searchTask` field was
    /// supposed to prevent: search A starts, search B supersedes it before A
    /// is released, and only then are both allowed to finish -- releasing the
    /// newer one (B) first and the stale one (A) last, the order most likely
    /// to let a stale response win if cancellation didn't actually work.
    @Test
    func aSupersededSearchCannotOverwriteTheNewerResults() async {
        let gate = SearchGate()
        let model = PostSongModel(
            search: GatedMusicSearchRepository(gate: gate, resultsByQuery: [
                "stale": [candidate("stale-id")],
                "fresh": [candidate("fresh-id")]
            ]),
            debounce: .zero
        )

        let taskA = Task { await model.queryChanged("stale") }
        await gate.waitUntilStarted("stale")

        let taskB = Task { await model.queryChanged("fresh") }
        await gate.waitUntilStarted("fresh")

        // Release the newer search first and the stale, superseded one last.
        await gate.release("fresh")
        await taskB.value

        await gate.release("stale")
        await taskA.value

        #expect(model.results.map(\.id) == ["spotify:fresh-id"])
        #expect(model.isSearching == false)
    }

    @Test
    func unrecognisedLinkIsReportedAtTheField() async {
        let model = PostSongModel(search: MockMusicSearchRepository(), debounce: .zero)

        await model.linkTextChanged("einfach nur text")

        #expect(model.selected == nil)
        #expect(model.errorMessage?.isEmpty == false)
    }

    /// Pins the real erasure case, distinct from the tab-remount case covered
    /// by `aSelectionMadeInSearchSurvivesSwitchingToLinkTabAndBack` below: the
    /// link field held actual resolved text, and the user cleared it, so the
    /// selection it produced must go away too.
    @Test
    func clearingTheLinkTextAfterASelectionClearsSelectedAndError() async {
        let oEmbed = SoundCloudOEmbedClient(performRequest: { _ in
            let data = Data("""
            {"title":"Some Track by Artist","author_name":"Artist",
             "thumbnail_url":"https://i1.sndcdn.com/artwork.jpg"}
            """.utf8)
            return (data, HTTPURLResponse(
                url: URL(string: "https://soundcloud.com/oembed")!,
                statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let model = PostSongModel(search: MockMusicSearchRepository(), oEmbed: oEmbed, debounce: .zero)
        await model.linkTextChanged("https://soundcloud.com/artist/some-track")
        #expect(model.selected != nil)

        await model.linkTextChanged("")

        #expect(model.selected == nil)
        #expect(model.errorMessage == nil)
    }

    /// Pins the fix for the tabs fighting over `selected`: switching the
    /// Picker to "Link einfügen" and back remounts each TextField, and
    /// SwiftUI's `.task(id:)` re-runs on that remount even though the bound
    /// text never actually changed. Before the fix, the Link tab's re-run
    /// with its still-empty text unconditionally cleared `selected` -- so a
    /// selection made by tapping a search result never survived a visit to
    /// the other tab and back. `queryChanged`/`linkTextChanged` must treat a
    /// call with unchanged text as a no-op rather than a real edit.
    @Test
    func aSelectionMadeInSearchSurvivesSwitchingToLinkTabAndBack() async {
        let model = PostSongModel(
            search: MockMusicSearchRepository(candidates: [candidate("a")]), debounce: .zero
        )
        await model.queryChanged("justice")
        model.select(candidate("a"))

        // Simulates the Link tab remounting with its untouched, still-empty
        // text -- not the user typing or erasing anything there.
        await model.linkTextChanged("")
        #expect(model.selected != nil)

        // Simulates switching back to Search, remounting with the same query
        // text that was already there.
        await model.queryChanged("justice")

        #expect(model.selected?.id == "spotify:a")
    }

    @Test
    func soundCloudLinkResolvesTitleAndArtistViaOEmbed() async {
        let oEmbed = SoundCloudOEmbedClient(performRequest: { _ in
            let data = Data("""
            {"title":"Some Track by Artist","author_name":"Artist",
             "thumbnail_url":"https://i1.sndcdn.com/artwork.jpg"}
            """.utf8)
            return (data, HTTPURLResponse(
                url: URL(string: "https://soundcloud.com/oembed")!,
                statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let model = PostSongModel(search: MockMusicSearchRepository(), oEmbed: oEmbed, debounce: .zero)

        await model.linkTextChanged("https://soundcloud.com/artist/some-track")

        #expect(model.selected?.title == "Some Track by Artist")
        #expect(model.selected?.artist == "Artist")
        #expect(model.selected?.source.service == .soundcloud)
        #expect(model.errorMessage == nil)
    }

    @Test
    func spotifyLinkResolvesTitleAndArtistViaOEmbed() async {
        let spotifyOEmbed = SpotifyOEmbedClient(performRequest: { _ in
            let data = Data("""
            {"title":"Genesis","thumbnail_url":"https://i.scdn.co/image/abc.jpg"}
            """.utf8)
            return (data, HTTPURLResponse(
                url: URL(string: "https://open.spotify.com/oembed")!,
                statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let model = PostSongModel(
            search: MockMusicSearchRepository(), spotifyOEmbed: spotifyOEmbed, debounce: .zero
        )

        await model.linkTextChanged("https://open.spotify.com/track/abc123")

        #expect(model.selected?.title == "Genesis")
        #expect(model.selected?.artist == "")
        #expect(model.selected?.source.serviceTrackID == "abc123")
        #expect(model.errorMessage == nil)
    }

    @Test
    func spotifyLinkFallsBackToRawLinkAndExplainsWhenMetadataLookupFails() async {
        let spotifyOEmbed = SpotifyOEmbedClient(performRequest: { _ in
            (Data(), HTTPURLResponse(
                url: URL(string: "https://open.spotify.com/oembed")!,
                statusCode: 429, httpVersion: nil, headerFields: nil)!)
        })
        let model = PostSongModel(
            search: MockMusicSearchRepository(), spotifyOEmbed: spotifyOEmbed, debounce: .zero
        )

        await model.linkTextChanged("https://open.spotify.com/track/abc123")

        #expect(model.selected?.source.serviceTrackID == "abc123")
        #expect(model.errorMessage?.contains("zu viele") == true)
    }
}

@Suite
@MainActor
struct PostSongSectionTests {
    private func candidate(seconds: Int?, id: String = "abc") -> TrackCandidate {
        TrackCandidate(
            title: "Genesis", artist: "Justice",
            source: TrackSource(
                service: .spotify, serviceTrackID: id,
                pageURL: URL(string: "https://open.spotify.com/track/\(id)")!, artworkURL: nil
            ),
            durationSeconds: seconds
        )
    }

    private func model() -> PostSongModel {
        PostSongModel(search: FailingMusicSearchRepository(error: .trackUnavailable))
    }

    @Test
    func choosingATrackOpensASectionInsideIt() {
        let model = model()

        model.select(candidate(seconds: 222))

        let section = model.section
        #expect(section?.duration == 30)
        #expect((section?.end ?? .infinity) <= 222)
    }

    /// A track shorter than the default window must not get a section that runs
    /// past its own end.
    @Test
    func aShortTrackGetsAShortSection() {
        let model = model()

        model.select(candidate(seconds: 12))

        #expect((model.section?.end ?? .infinity) <= 12)
    }

    /// Without a length the picker works from an assumption, so the section has
    /// to fit that assumption rather than nothing at all.
    @Test
    func aTrackWithoutALengthStillGetsASection() {
        let model = model()

        model.select(candidate(seconds: nil))

        #expect(model.section?.duration == 30)
        #expect((model.section?.end ?? .infinity) <= TrackSection.assumedDuration)
    }

    /// Picking a different track must not carry the previous track's window
    /// across -- the timestamps would point into a song nobody chose.
    @Test
    func choosingAnotherTrackStartsItsSectionFresh() {
        let model = model()
        model.select(candidate(seconds: 222, id: "long"))
        model.section?.move(toStart: 180, in: 222)

        model.select(candidate(seconds: 60, id: "short"))

        #expect((model.section?.end ?? .infinity) <= 60)
    }

    /// Landing on the same track again -- tapping it twice, or a re-render --
    /// must not throw away a window the poster already positioned.
    @Test
    func choosingTheSameTrackAgainKeepsTheWindowWhereItWas() {
        let model = model()
        model.select(candidate(seconds: 222))
        model.section?.move(toStart: 180, in: 222)

        model.select(candidate(seconds: 222))

        #expect(model.section?.start == 180)
    }

    @Test
    func clearingTheSelectionClearsTheSection() async {
        let model = model()
        model.select(candidate(seconds: 222))

        await model.queryChanged("etwas anderes")

        #expect(model.section == nil)
    }
}

@Suite
@MainActor
struct PostSongSpinnerTests {
    /// The two cancellation exits inside the search task skip the line that
    /// clears this flag. No reachable path leaves it stuck today -- the only
    /// canceller is `queryChanged`, which always sets the flag again right
    /// after -- so this pins the invariant rather than reproducing a bug.
    @Test
    func theSpinnerIsOffOnceASupersededSearchHasSettled() async {
        let model = PostSongModel(
            search: FailingMusicSearchRepository(error: .trackUnavailable),
            debounce: .zero
        )

        await model.queryChanged("daf")
        await model.queryChanged("daft")

        #expect(model.isSearching == false)
    }

    @Test
    func clearingTheFieldStopsTheSpinner() async {
        let model = PostSongModel(
            search: FailingMusicSearchRepository(error: .trackUnavailable),
            debounce: .zero
        )
        await model.queryChanged("daft")

        await model.queryChanged("")

        #expect(model.isSearching == false)
    }
}
