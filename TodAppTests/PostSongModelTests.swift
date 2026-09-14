import Foundation
import Testing
@testable import TodApp

/// Lets a test hold a `searchTracks` call open until it explicitly releases
/// it, and lets the test know once the call has actually started waiting --
/// so two overlapping `queryChanged` calls can be driven into a real race
/// instead of hoping timing works out. Wired into a `FakeMusicProvider`'s
/// injectable `search` closure rather than a standalone repository now that
/// `PostSongModel` talks to a provider.
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

@Suite
@MainActor
struct PostSongModelTests {
    /// What a signed-in provider that can search (but not play) declares --
    /// enough for every test below that needs `queryChanged` to actually
    /// reach the fake's `search` closure instead of failing at the
    /// `canSearch` gate.
    private var canSearchOnly: MusicProviderCapabilities {
        MusicProviderCapabilities(
            canSearch: true, canPlayFullTracks: false,
            canStartAtPosition: false, playsInsideTheApp: false
        )
    }

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
        let expected = candidate("a")
        let model = PostSongModel(
            provider: FakeMusicProvider(capabilities: canSearchOnly, search: { _ in [expected] }),
            debounce: .zero
        )

        await model.queryChanged("justice")

        #expect(model.results.map(\.id) == ["spotify:a"])
        #expect(model.isSearching == false)
    }

    /// A rejected session must not be reported as a connection problem: it
    /// would send the user to check their network when they need to sign in
    /// again. The old version of this test pinned a message pointing at
    /// Secrets.xcconfig, a file this app no longer ships.
    @Test
    func aRejectedSessionIsNotReportedAsAConnectionProblem() async {
        let model = PostSongModel(
            provider: FakeMusicProvider(
                capabilities: canSearchOnly,
                search: { _ in throw TodAppError.authorizationFailed }
            ),
            debounce: .zero
        )

        await model.queryChanged("justice")

        #expect(model.results.isEmpty)
        #expect(model.errorMessage?.contains("Anmeldung") == true)
        #expect(model.errorMessage?.contains("Verbindung") == false)
    }

    @Test
    func rateLimitIsReportedSeparatelyFromOtherFailures() async {
        let model = PostSongModel(
            provider: FakeMusicProvider(
                capabilities: canSearchOnly,
                search: { _ in throw TodAppError.rateLimited }
            ),
            debounce: .zero
        )

        await model.queryChanged("justice")

        #expect(model.errorMessage?.contains("zu viele") == true)
    }

    @Test
    func clearingTheQueryClearsResultsAndError() async {
        let expected = candidate("a")
        let model = PostSongModel(
            provider: FakeMusicProvider(capabilities: canSearchOnly, search: { _ in [expected] }),
            debounce: .zero
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
        let resultsByQuery: [String: [TrackCandidate]] = [
            "stale": [candidate("stale-id")],
            "fresh": [candidate("fresh-id")]
        ]
        let model = PostSongModel(
            provider: FakeMusicProvider(capabilities: canSearchOnly, search: { query in
                await gate.markStarted(query)
                await gate.waitForRelease(query)
                return resultsByQuery[query] ?? []
            }),
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
        let model = PostSongModel(provider: FakeMusicProvider(capabilities: .none), debounce: .zero)

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
        let model = PostSongModel(
            provider: FakeMusicProvider(capabilities: .none), oEmbed: oEmbed, debounce: .zero
        )
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
        let expected = candidate("a")
        let model = PostSongModel(
            provider: FakeMusicProvider(capabilities: canSearchOnly, search: { _ in [expected] }),
            debounce: .zero
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
        let model = PostSongModel(
            provider: FakeMusicProvider(capabilities: .none), oEmbed: oEmbed, debounce: .zero
        )

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
            provider: FakeMusicProvider(capabilities: .none), spotifyOEmbed: spotifyOEmbed, debounce: .zero
        )

        await model.linkTextChanged("https://open.spotify.com/track/abc123")

        #expect(model.selected?.title == "Genesis")
        #expect(model.selected?.artist == "")
        #expect(model.selected?.source.serviceTrackID == "abc123")
        #expect(model.errorMessage == nil)
    }

    /// A typed link starts one lookup per keystroke. An older lookup that fails
    /// late -- here for the link still one character short -- must not land
    /// after the finished one: in the simulator it put "Prüf deine Verbindung"
    /// under a song that had resolved fine.
    @Test(.timeLimit(.minutes(1)))
    func aSupersededLinkLookupCannotOverwriteTheNewerOne() async {
        let gate = SearchGate()
        let spotifyOEmbed = SpotifyOEmbedClient(performRequest: { request in
            let asked = request.url?.absoluteString ?? ""
            if !asked.contains("abc1234") {
                await gate.markStarted("older")
                await gate.waitForRelease("older")
                throw URLError(.networkConnectionLost)
            }
            let data = Data("""
            {"title":"Blinding Lights","thumbnail_url":"https://i.scdn.co/image/abc.jpg"}
            """.utf8)
            return (data, HTTPURLResponse(
                url: URL(string: "https://open.spotify.com/oembed")!,
                statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let model = PostSongModel(
            provider: FakeMusicProvider(capabilities: .none), spotifyOEmbed: spotifyOEmbed, debounce: .zero
        )

        let older = Task { await model.linkTextChanged("https://open.spotify.com/track/abc123") }
        await gate.waitUntilStarted("older")
        await model.linkTextChanged("https://open.spotify.com/track/abc1234")
        await gate.release("older")
        await older.value

        #expect(model.selected?.title == "Blinding Lights")
        #expect(model.selected?.source.serviceTrackID == "abc1234")
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
            provider: FakeMusicProvider(capabilities: .none), spotifyOEmbed: spotifyOEmbed, debounce: .zero
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
        PostSongModel(provider: FakeMusicProvider(capabilities: .none))
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
            provider: FakeMusicProvider(capabilities: .none),
            debounce: .zero
        )

        await model.queryChanged("daf")
        await model.queryChanged("daft")

        #expect(model.isSearching == false)
    }

    @Test
    func clearingTheFieldStopsTheSpinner() async {
        let model = PostSongModel(
            provider: FakeMusicProvider(capabilities: .none),
            debounce: .zero
        )
        await model.queryChanged("daft")

        await model.queryChanged("")

        #expect(model.isSearching == false)
    }
}

/// `.authorizationFailed`, `.tokenStorageFailed`, `.noActivePlaybackDevice`
/// and `.playbackNotAvailable` used to have no case in `message(for:)` and
/// fell through to the generic "check your connection" text -- wrong for all
/// four, since none of them is a connectivity problem. Each test below pins
/// one case to its own, distinct copy so a later edit cannot quietly
/// collapse it back onto the generic fallback.
@Suite
@MainActor
struct PostSongModelAuthAndPlaybackMessageTests {
    private var genericMessage: String {
        // `.notFound` has no dedicated case, so this is exactly the fallback
        // text a regression would collapse the four cases below back onto.
        PostSongModel.message(for: TodAppError.notFound)
    }

    @Test
    func authorizationFailedExplainsSignInDidNotCompleteAndSuggestsRetrying() {
        let message = PostSongModel.message(for: TodAppError.authorizationFailed)

        #expect(message != genericMessage)
        #expect(message.contains("Anmeldung"))
    }

    @Test
    func tokenStorageFailedExplainsTheDeviceCouldNotSaveIt() {
        let message = PostSongModel.message(for: TodAppError.tokenStorageFailed)

        #expect(message != genericMessage)
        #expect(message.contains("gespeichert"))
    }

    @Test
    func noActivePlaybackDeviceTellsThePersonToOpenSpotifySomewhere() {
        let message = PostSongModel.message(for: TodAppError.noActivePlaybackDevice)

        #expect(message != genericMessage)
        #expect(message.contains("Spotify"))
    }

    @Test
    func playbackNotAvailableNamesPremiumAsTheRequirement() {
        let message = PostSongModel.message(for: TodAppError.playbackNotAvailable)

        #expect(message != genericMessage)
        #expect(message.contains("Premium"))
    }

    /// Belt and braces on top of the four checks above: even if two of them
    /// were quietly collapsed onto the *same* new string (rather than back
    /// onto the generic fallback), that would slip past each individual
    /// `!= genericMessage` check but not past this one.
    @Test
    func allFourMessagesAreDistinctFromEachOtherAndFromTheGenericFallback() {
        let messages = [
            genericMessage,
            PostSongModel.message(for: TodAppError.authorizationFailed),
            PostSongModel.message(for: TodAppError.tokenStorageFailed),
            PostSongModel.message(for: TodAppError.noActivePlaybackDevice),
            PostSongModel.message(for: TodAppError.playbackNotAvailable),
        ]

        #expect(Set(messages).count == messages.count)
    }
}

/// Picking the stretch of a song is everyone's; playing it back is not.
@Suite
@MainActor
struct SectionPickingTests {
    private func candidate() -> TrackCandidate {
        TrackCandidate(
            title: "Genesis", artist: "Justice",
            source: TrackSource(
                service: .spotify, serviceTrackID: "abc",
                pageURL: URL(string: "https://open.spotify.com/track/abc")!,
                artworkURL: nil
            ),
            durationSeconds: 220
        )
    }

    /// An account that can play nothing at all still gets a section to set --
    /// the picker is offered on selection, not on a capability.
    @Test
    func aSectionIsOfferedEvenWithNoPlaybackAtAll() {
        // A provider that can do nothing at all -- not even search.
        let model = PostSongModel(provider: FakeMusicProvider(capabilities: .none))

        model.select(candidate())

        #expect(model.section != nil)
    }

    /// And it survives the post, so whoever does have Premium hears the stretch
    /// the person without it picked.
    @Test
    func aSectionPickedWithoutPremiumIsStoredOnTheSubmission() async {
        let repo = InMemoryRepository()
        let store = AppStore(
            groupRepo: repo, submissionRepo: repo, voteRepo: repo,
            chatRepo: repo, battleRepo: repo
        )
        await store.loadGroups()
        store.selectGroup("wg")
        #expect(store.capabilities.canStartAtPosition == false)

        await store.post(candidate: candidate(), section: TrackSection(start: 62, end: 92))

        let posted = store.currentGroup?.submissions.first { $0.track == "Genesis" && $0.section != nil }
        #expect(posted?.section?.start == 62)
        #expect(posted?.section?.end == 92)
    }
}
