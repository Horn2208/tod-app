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

    // MARK: The preview mark

    @Test
    func applesPreviewIsMarked() {
        #expect(QuickPlay.playsPreview(.preview, spotifySession: true, measuredWholeSong: nil))
    }

    @Test
    func aWholeSongIsNeverMarked() {
        #expect(!QuickPlay.playsPreview(.wholeSong, spotifySession: false, measuredWholeSong: nil))
    }

    /// Before the embed has played this track, the login is all there is to go on.
    @Test
    func spotifysEmbedIsMarkedWithoutALogin() {
        #expect(QuickPlay.playsPreview(.embed, spotifySession: false, measuredWholeSong: nil))
        #expect(!QuickPlay.playsPreview(.embed, spotifySession: true, measuredWholeSong: nil))
    }

    /// Once it has played, what Spotify reported wins over the guess -- a login
    /// without Premium still gets the excerpt.
    @Test
    func whatTheEmbedReportedWins() {
        #expect(QuickPlay.playsPreview(.embed, spotifySession: true, measuredWholeSong: false))
        #expect(!QuickPlay.playsPreview(.embed, spotifySession: false, measuredWholeSong: true))
    }

    @Test
    func nothingToPlayIsNotMarked() {
        #expect(!QuickPlay.playsPreview(.wait, spotifySession: false, measuredWholeSong: nil))
        #expect(!QuickPlay.playsPreview(.hidden, spotifySession: false, measuredWholeSong: nil))
    }
}
