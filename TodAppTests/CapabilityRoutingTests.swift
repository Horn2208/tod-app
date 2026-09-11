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
/// `TrackPlayerSheet.player(for:catalog:spotifyWebSession:)`.
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

    /// The one place the section stops being decoration: a provider that can
    /// start at a position is handed the section, and one that cannot is not
    /// offered the button at all.
    @Test
    func onlyAProviderThatCanSeekIsGivenTheSection() async throws {
        let seeking = FakeMusicProvider(
            capabilities: MusicProviderCapabilities(
                canSearch: true, canPlayFullTracks: true,
                canStartAtPosition: true, playsInsideTheApp: false
            )
        )
        let source = TrackSource(
            service: .soundcloud, serviceTrackID: "x",
            pageURL: URL(string: "https://soundcloud.com/a/b")!, artworkURL: nil
        )

        try await seeking.play(source, from: TrackSection(start: 82, end: 112))

        #expect(await seeking.playedSection == TrackSection(start: 82, end: 112))
    }

    private var match: CatalogResolver.Outcome {
        .found(CatalogSong(id: "1499378607", title: "Blinding Lights", artist: "The Weeknd"))
    }

    /// No flash of Spotify's player while the catalog is still being asked.
    @Test
    func spotifyWaitsForTheCatalogBeforeChoosing() {
        #expect(TrackPlayerSheet.player(for: .spotify, catalog: nil, spotifyWebSession: false) == .waiting)
    }

    @Test
    func aCatalogMatchPlaysApplesPreview() {
        #expect(TrackPlayerSheet.player(for: .spotify, catalog: match, spotifyWebSession: false) == .applePreview)
    }

    /// "Nights" is not in the iTunes Store. It still plays -- through Spotify.
    @Test
    func noMatchFallsBackToSpotifysEmbed() {
        #expect(TrackPlayerSheet.player(for: .spotify, catalog: .notInCatalog, spotifyWebSession: false) == .own)
    }

    /// A Spotify login in the player may bring the whole song; Apple's
    /// preview never does. The login wins over a match.
    @Test
    func aSpotifyLoginInThePlayerKeepsTheEmbed() {
        #expect(TrackPlayerSheet.player(for: .spotify, catalog: match, spotifyWebSession: true) == .own)
    }

    /// SoundCloud publishes no API a player could be driven through and has
    /// no catalog twin, so it keeps its own widget whatever else is known.
    @Test
    func soundCloudKeepsItsWidget() {
        #expect(TrackPlayerSheet.player(for: .soundcloud, catalog: match, spotifyWebSession: false) == .widget)
        #expect(!TrackPlayerSheet.looksUpCatalog(for: .soundcloud))
    }
}
