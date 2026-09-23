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
        let route = TrackPlayerSheet.player(for: .spotify, catalog: .found(song))
        #expect(QuickPlay.action(for: route) == .preview)
    }

    @Test
    func aSpotifyPostWithoutAMatchDrivesTheEmbed() {
        let route = TrackPlayerSheet.player(for: .spotify, catalog: .notInCatalog)
        #expect(QuickPlay.action(for: route) == .embed)
    }

    @Test
    func wholeSongsWinForASubscriber() {
        let song = CatalogSong(id: "1", title: "Nights", artist: "Frank Ocean")
        let route = TrackPlayerSheet.player(
            for: .spotify, catalog: .found(song), appleMusicWholeSongs: true)
        #expect(QuickPlay.action(for: route) == .wholeSong)
    }

    @Test
    func theButtonWaitsWhileTheCatalogIsAsked() {
        let route = TrackPlayerSheet.player(for: nil, catalog: nil)
        #expect(QuickPlay.action(for: route) == .wait)
    }

    /// SoundCloud's widget lives in the song's sheet, and a post Apple does not
    /// know has nothing to start. No button there, rather than one that does
    /// nothing.
    @Test
    func noButtonWhereNothingCanBeStartedFromTheCard() {
        let soundCloud = TrackPlayerSheet.player(for: .soundcloud, catalog: nil)
        let unknown = TrackPlayerSheet.player(for: nil, catalog: .notInCatalog)
        #expect(QuickPlay.action(for: soundCloud) == .hidden)
        #expect(QuickPlay.action(for: unknown) == .hidden)
    }

    // MARK: The preview mark

    @Test
    func applesPreviewIsMarked() {
        #expect(QuickPlay.playsPreview(.preview))
    }

    @Test
    func aWholeSongIsNeverMarked() {
        #expect(!QuickPlay.playsPreview(.wholeSong))
    }

    /// The embed plays signed out, so what it plays is always Spotify's excerpt.
    @Test
    func spotifysEmbedIsAlwaysMarked() {
        #expect(QuickPlay.playsPreview(.embed))
    }

    @Test
    func nothingToPlayIsNotMarked() {
        #expect(!QuickPlay.playsPreview(.wait))
        #expect(!QuickPlay.playsPreview(.hidden))
    }
}
