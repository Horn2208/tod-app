import Testing
@testable import TodApp

/// The line under the section picker names the ways a listener hears the pick
/// from its start -- and only the ways that exist for where the song is from.
@Suite
struct SectionReachTests {
    /// Spotify's embed plays signed out, so its excerpt only: the one way to
    /// the pick is Apple Music's whole song.
    @Test
    func aSpotifySongNamesOnlyAppleMusic() {
        let note = SectionReach.note(for: .spotify)
        #expect(note?.contains("Spotify Premium") == false)
        #expect(note?.contains("Apple-Music-Abo") == true)
    }

    /// Without a Spotify link, Spotify has no part in it.
    @Test
    func aSongWithoutALinkNamesOnlyAppleMusic() {
        let note = SectionReach.note(for: nil)
        #expect(note?.contains("Apple-Music-Abo") == true)
        #expect(note?.contains("Spotify") == false)
    }

    /// SoundCloud's widget plays from the start for everyone, and says so
    /// itself; a subscription changes nothing there.
    @Test
    func soundCloudGetsNoLine() {
        #expect(SectionReach.note(for: .soundcloud) == nil)
    }
}
