import Testing
@testable import TodApp

/// The feed card's play button follows the song's own player: the same route,
/// and a button only where that route can be driven from outside the sheet.
@MainActor
@Suite
struct QuickPlayTests {
    @Test
    func aSpotifyPostPlaysApplesPreviewWhenTheCatalogHasIt() {
        let song = CatalogSong(id: "1", title: "Nights", artist: "Frank Ocean")
        let route = TrackPlayerSheet.player(for: .spotify, catalog: .found(song), spotifyWebSession: false)
        #expect(QuickPlay.action(for: route) == .preview)
    }

    @Test
    func aSpotifyPostWithoutAMatchDrivesTheEmbed() {
        let route = TrackPlayerSheet.player(for: .spotify, catalog: .notInCatalog, spotifyWebSession: false)
        #expect(QuickPlay.action(for: route) == .embed)
    }

    @Test
    func wholeSongsWinForASubscriber() {
        let song = CatalogSong(id: "1", title: "Nights", artist: "Frank Ocean")
        let route = TrackPlayerSheet.player(
            for: .spotify, catalog: .found(song), spotifyWebSession: true, appleMusicWholeSongs: true)
        #expect(QuickPlay.action(for: route) == .wholeSong)
    }

    @Test
    func theButtonWaitsWhileTheCatalogIsAsked() {
        let route = TrackPlayerSheet.player(for: nil, catalog: nil, spotifyWebSession: false)
        #expect(QuickPlay.action(for: route) == .wait)
    }

    /// SoundCloud's widget lives in the song's sheet, and a post Apple does not
    /// know has nothing to start. No button there, rather than one that does
    /// nothing.
    @Test
    func noButtonWhereNothingCanBeStartedFromTheCard() {
        let soundCloud = TrackPlayerSheet.player(for: .soundcloud, catalog: nil, spotifyWebSession: false)
        let unknown = TrackPlayerSheet.player(for: nil, catalog: .notInCatalog, spotifyWebSession: false)
        #expect(QuickPlay.action(for: soundCloud) == .hidden)
        #expect(QuickPlay.action(for: unknown) == .hidden)
    }
}
