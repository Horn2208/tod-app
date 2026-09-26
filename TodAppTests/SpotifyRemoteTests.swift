import Foundation
import Testing
@testable import TodApp

/// Where App Remote moves the song once it is connected.
@Suite
struct SpotifyRemoteTests {
    @Test
    func theSectionStartIsSentInMilliseconds() {
        #expect(SpotifyRemote.seekPosition(start: 70) == 70_000)
        #expect(SpotifyRemote.seekPosition(start: 34.666) == 34_666)
    }

    /// The very start needs no seek: the song already begins there.
    @Test
    func noSeekForTheStart() {
        #expect(SpotifyRemote.seekPosition(start: nil) == nil)
        #expect(SpotifyRemote.seekPosition(start: 0.4) == nil)
    }
}

/// Spotify says where it is and when; between its reports the player counts
/// on by itself.
@Suite
struct RemoteClockTests {
    private let then = Date(timeIntervalSince1970: 1_000)

    @Test
    func aPlayingSongCountsOn() {
        let clock = RemoteClock(positionMs: 70_000, at: then, isPaused: false, durationMs: 240_000)

        #expect(clock.position(at: then.addingTimeInterval(5)) == 75)
    }

    @Test
    func aPausedSongStaysWhereItIs() {
        let clock = RemoteClock(positionMs: 70_000, at: then, isPaused: true, durationMs: 240_000)

        #expect(clock.position(at: then.addingTimeInterval(5)) == 70)
    }

    /// Counting on stops at the end: past it Spotify has moved on, and says so.
    @Test
    func theCountStopsAtTheEnd() {
        let clock = RemoteClock(positionMs: 238_000, at: then, isPaused: false, durationMs: 240_000)

        #expect(clock.position(at: then.addingTimeInterval(10)) == 240)
    }

    @Test
    func theSongIsKnownByItsURI() {
        let source = TrackSource(
            service: .spotify, serviceTrackID: "51KP8yo3FnpKJtrQIsriu4",
            pageURL: URL(string: "https://open.spotify.com/track/51KP8yo3FnpKJtrQIsriu4")!)

        #expect(SpotifyRemote.uri(for: source) == "spotify:track:51KP8yo3FnpKJtrQIsriu4")
    }
}

/// When App Remote moves the song to the section: only once Spotify reports
/// this song playing, and no longer once it is there.
@Suite
struct RemoteSectionSeekTests {
    private let song = "spotify:track:abc"

    /// Right after connecting, Spotify may still be on the song before.
    @Test
    func waitsWhileAnotherSongIsReported() {
        #expect(RemoteSectionSeek.decide(
            targetURI: song, startMs: 70_000, reportedURI: "spotify:track:old", positionMs: 5_000, isPaused: false)
            == .wait)
    }

    /// A seek before the song plays was lost on the phone: it then began at 0.
    @Test
    func waitsWhileTheSongIsNotPlayingYet() {
        #expect(RemoteSectionSeek.decide(
            targetURI: song, startMs: 70_000, reportedURI: song, positionMs: 0, isPaused: true)
            == .wait)
    }

    @Test
    func seeksOnceTheSongPlaysFromTheTop() {
        #expect(RemoteSectionSeek.decide(
            targetURI: song, startMs: 70_000, reportedURI: song, positionMs: 400, isPaused: false)
            == .seek(toMs: 70_000))
    }

    /// Spotify's report comes a moment after the seek, a little short of it.
    @Test
    func atTheSectionItIsDone() {
        #expect(RemoteSectionSeek.decide(
            targetURI: song, startMs: 70_000, reportedURI: song, positionMs: 69_200, isPaused: false)
            == .done)
    }

    @Test
    func withoutASectionThereIsNothingToDo() {
        #expect(RemoteSectionSeek.decide(
            targetURI: song, startMs: nil, reportedURI: song, positionMs: 0, isPaused: false)
            == .done)
    }
}
