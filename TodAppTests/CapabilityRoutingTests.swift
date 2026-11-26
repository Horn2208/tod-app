import Foundation
import Testing
@testable import TodApp

/// Views used to decide what to offer by asking `TrackSource.service ==
/// .spotify`. That question is now illegal for anything except a genuine
/// presentation fact about a specific service (embed height, link label) --
/// what the app *offers* has to come from the signed-in provider's declared
/// capabilities instead. These tests pin where that holds -- the search box --
/// and the one place it deliberately does not: the player routes by service,
/// because which player a service *can* have is a fact about the service. See
/// `TrackPlayerSheet.player(for:catalog:appleMusicWholeSongs:)`.
@Suite
@MainActor
struct CapabilityRoutingTests {
    /// The search box talks to whichever provider is signed in, with no idea
    /// which service that is.
    @Test
    func theSearchGoesThroughTheProvider() async {
        let provider = FakeMusicProvider(
            capabilities: MusicProviderCapabilities(
                canSearch: true, canPlayFullTracks: false,
                canStartAtPosition: false, playsInsideTheApp: false
            )
        )
        let model = PostSongModel(provider: provider, debounce: .zero)

        await model.queryChanged("daft punk")

        #expect(model.results.isEmpty)
        #expect(model.errorMessage == nil)
    }

    @Test
    func aProviderThatCannotSearchReportsItInTheField() async {
        let provider = FakeMusicProvider(capabilities: .none)
        let model = PostSongModel(provider: provider, debounce: .zero)

        await model.queryChanged("daft punk")

        #expect(model.errorMessage == PostSongModel.message(for: TodAppError.searchUnavailable))
    }

    private var match: CatalogResolver.Outcome {
        .found(CatalogSong(id: "1499378607", title: "Blinding Lights", artist: "The Weeknd"))
    }

    /// No flash of Spotify's player while the catalog is still being asked.
    @Test
    func spotifyWaitsForTheCatalogBeforeChoosing() {
        #expect(TrackPlayerSheet.player(for: .spotify, catalog: nil) == .waiting)
    }

    @Test
    func aCatalogMatchPlaysApplesPreview() {
        #expect(TrackPlayerSheet.player(for: .spotify, catalog: match) == .applePreview)
    }

    /// "Nights" is not in the iTunes Store. It still plays -- through Spotify.
    @Test
    func noMatchFallsBackToSpotifysEmbed() {
        #expect(TrackPlayerSheet.player(for: .spotify, catalog: .notInCatalog) == .own)
    }

    /// A song posted without a link has only Apple. With a match it plays;
    /// without one there is nothing to play, and the screen says so instead of
    /// offering a dead button.
    @Test
    func aSongWithoutALinkPlaysWhenAppleHasIt() {
        #expect(TrackPlayerSheet.player(for: nil, catalog: match) == .applePreview)
        #expect(TrackPlayerSheet.player(for: nil, catalog: .notInCatalog) == .none)
        #expect(TrackPlayerSheet.player(for: nil, catalog: nil) == .waiting)
        #expect(TrackPlayerSheet.looksUpCatalog(for: nil))
    }

    /// SoundCloud publishes no API a player could be driven through and has
    /// no catalog twin, so it keeps its own widget whatever else is known.
    @Test
    func soundCloudKeepsItsWidget() {
        #expect(TrackPlayerSheet.player(for: .soundcloud, catalog: match) == .widget)
        #expect(!TrackPlayerSheet.looksUpCatalog(for: .soundcloud))
    }

    /// Connected to Spotify: Spotify's own preview, even where Apple has the
    /// same recording -- and at once, without waiting for Apple's answer.
    @Test
    func connectedToSpotifyItIsSpotifysPreview() {
        #expect(TrackPlayerSheet.player(for: .spotify, catalog: match, prefersSpotify: true) == .own)
        #expect(TrackPlayerSheet.player(for: .spotify, catalog: nil, prefersSpotify: true) == .own)
    }

    /// Not connected: Apple's preview where Apple has the song, as before.
    @Test
    func notConnectedItStaysApplesPreview() {
        #expect(TrackPlayerSheet.player(for: .spotify, catalog: match, prefersSpotify: false) == .applePreview)
    }

    /// A whole song from Apple Music still beats any preview.
    @Test
    func applesWholeSongStillComesFirst() {
        #expect(TrackPlayerSheet.player(
            for: .spotify, catalog: match, appleMusicWholeSongs: true, prefersSpotify: true) == .appleMusic)
    }

    /// Without a Spotify link there is no Spotify preview to prefer.
    @Test
    func aPostWithoutALinkStaysWithApple() {
        #expect(TrackPlayerSheet.player(for: nil, catalog: match, prefersSpotify: true) == .applePreview)
        #expect(TrackPlayerSheet.player(for: .soundcloud, catalog: match, prefersSpotify: true) == .widget)
    }
}
