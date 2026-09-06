import Foundation
import Testing
@testable import TodApp

/// Views used to decide what to offer by asking `TrackSource.service ==
/// .spotify`. That question is now illegal for anything except a genuine
/// presentation fact about a specific service (embed height, link label) --
/// what the app *offers* has to come from the signed-in provider's declared
/// capabilities instead. These tests pin the two places that decision now
/// lives: the search box, and the player.
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

    /// The player itself must make the identical decision from the identical
    /// signal -- not from `source.service`. A provider that can start at a
    /// position gets the native player and no embed at all.
    @Test
    func aProviderThatCanSeekGetsTheNativePlayer() {
        let capabilities = MusicProviderCapabilities(
            canSearch: true, canPlayFullTracks: true,
            canStartAtPosition: true, playsInsideTheApp: false
        )

        #expect(TrackPlayerSheet.mode(for: capabilities) == .native)
    }

    /// Anything short of that -- no sign-in, a free account, a provider that
    /// can play but not seek -- keeps today's embed rather than offering a
    /// native player that cannot honour the picked section.
    @Test
    func aProviderThatCannotSeekKeepsTheEmbed() {
        let capabilities = MusicProviderCapabilities(
            canSearch: true, canPlayFullTracks: true,
            canStartAtPosition: false, playsInsideTheApp: false
        )

        #expect(TrackPlayerSheet.mode(for: capabilities) == .embed)
    }

    @Test
    func noSignInAtAllAlsoKeepsTheEmbed() {
        #expect(TrackPlayerSheet.mode(for: .none) == .embed)
    }
}
