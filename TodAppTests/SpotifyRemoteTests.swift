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
