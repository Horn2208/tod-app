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
