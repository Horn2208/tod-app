import Foundation
import Testing
@testable import TodApp

/// Where whole songs from Apple Music sit among the players. They win whenever
/// the catalog has the song -- over the preview, and over a Spotify login in
/// the player, because only they start at the picked section natively.
/// On the main actor, like `CapabilityRoutingTests`: the routing lives on a
/// view, and a view's statics are main-actor isolated.
@MainActor
@Suite
struct WholeSongRoutingTests {
    private let match = CatalogResolver.Outcome.found(
        CatalogSong(id: "1499378607", title: "Blinding Lights", artist: "The Weeknd"))

    @Test
    func wholeSongsReplaceThePreview() {
        #expect(TrackPlayerSheet.player(
            for: .spotify, catalog: match, spotifyWebSession: false, appleMusicWholeSongs: true) == .appleMusic)
    }

    @Test
    func wholeSongsWinOverASpotifyLoginInThePlayer() {
        #expect(TrackPlayerSheet.player(
            for: .spotify, catalog: match, spotifyWebSession: true, appleMusicWholeSongs: true) == .appleMusic)
    }

    /// With a Spotify login the embed would otherwise show for the moment the
    /// catalog takes, and then be swapped out under the listener's thumb.
    @Test
    func wholeSongsWaitForTheCatalogRatherThanFlashTheEmbed() {
        #expect(TrackPlayerSheet.player(
            for: .spotify, catalog: nil, spotifyWebSession: true, appleMusicWholeSongs: true) == .waiting)
    }

    @Test
    func withoutAnAppleMatchSpotifyStillPlays() {
        #expect(TrackPlayerSheet.player(
            for: .spotify, catalog: .notInCatalog, spotifyWebSession: false, appleMusicWholeSongs: true) == .own)
        #expect(TrackPlayerSheet.player(
            for: .spotify, catalog: .notInCatalog, spotifyWebSession: true, appleMusicWholeSongs: true) == .own)
    }

    @Test
    func aSongWithoutALinkPlaysWholeWhenAppleHasIt() {
        #expect(TrackPlayerSheet.player(
            for: nil, catalog: match, spotifyWebSession: false, appleMusicWholeSongs: true) == .appleMusic)
    }

    /// Without a subscription that plays catalog songs, nothing changes.
    @Test
    func withoutWholeSongsThePreviewStays() {
        #expect(TrackPlayerSheet.player(
            for: .spotify, catalog: match, spotifyWebSession: false, appleMusicWholeSongs: false) == .applePreview)
    }

    @Test
    func soundCloudKeepsItsWidgetEvenWithWholeSongs() {
        #expect(TrackPlayerSheet.player(
            for: .soundcloud, catalog: match, spotifyWebSession: false, appleMusicWholeSongs: true) == .widget)
    }
}
