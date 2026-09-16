import Testing
@testable import TodApp

/// While posting, playback is drawn on the song's own line -- but only where
/// its place in the song is known.
@MainActor
@Suite
struct SongPositionTests {
    @Test
    func aWholeSongFromAppleMusicIsDrawnWhereItIs() {
        let position = TrackPlayerSheet.songPosition(
            on: .appleMusic, isThisTrack: true, position: 72, playsWholeSong: true)
        #expect(position == 72)
    }

    /// Apple does not say where its 30 seconds lie in the song.
    @Test
    func aPreviewIsNotPlacedOnTheSong() {
        let position = TrackPlayerSheet.songPosition(
            on: .applePreview, isThisTrack: true, position: 12, playsWholeSong: false)
        #expect(position == nil)
    }

    @Test
    func spotifyIsPlacedOnlyWhenItPlaysTheWholeSong() {
        let whole = TrackPlayerSheet.songPosition(
            on: .own, isThisTrack: true, position: 95, playsWholeSong: true)
        let excerpt = TrackPlayerSheet.songPosition(
            on: .own, isThisTrack: true, position: 12, playsWholeSong: false)
        #expect(whole == 95)
        #expect(excerpt == nil)
    }

    /// Another song playing says nothing about this one.
    @Test
    func anotherTrackPlayingDrawsNothing() {
        let position = TrackPlayerSheet.songPosition(
            on: .appleMusic, isThisTrack: false, position: 72, playsWholeSong: true)
        #expect(position == nil)
    }
}
