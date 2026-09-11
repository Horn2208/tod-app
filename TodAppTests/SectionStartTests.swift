import Foundation
import Testing
@testable import TodApp

/// Whether a picked start can be honoured is decided from what Spotify reports
/// it is playing -- whole song or excerpt -- not from the account.
@Suite
struct SectionStartTests {
    @Test
    func aStartPlaybackIsAlreadyAtIsLeftAlone() {
        #expect(SectionStart.decide(start: 62, position: 62.4, duration: 200) == .inPlace)
    }

    /// The first report comes a moment after playback began, so "there" has
    /// some slack -- but not so much that a missed start passes as taken.
    @Test
    func thereHasSlackButNotMuch() {
        #expect(SectionStart.decide(start: 62, position: 63.9, duration: 200) == .inPlace)
        #expect(SectionStart.decide(start: 62, position: 64.5, duration: 200) == .seek(to: 62))
    }

    /// The load may not take the timestamp; the whole song is playing, from
    /// the top. Then the start is reached by seeking.
    @Test
    func aStartTheLoadDidNotTakeIsSoughtTo() {
        #expect(SectionStart.decide(start: 62, position: 0.3, duration: 200) == .seek(to: 62))
    }

    /// The excerpt is Spotify's choice of where in the song to cut, and it
    /// does not say where. A time in the song cannot be found in it.
    @Test
    func aStartIsNotInTheExcerptEvenAnEarlyOne() {
        #expect(SectionStart.decide(start: 62, position: 0.3, duration: 30) == .outsideWhatPlays)
        #expect(SectionStart.decide(start: 12, position: 0.3, duration: 30) == .outsideWhatPlays)
    }

    /// 22 seconds has been measured for one excerpt; shorter ones count too.
    @Test
    func aShorterExcerptIsStillTheExcerpt() {
        #expect(SectionStart.decide(start: 5, position: 0, duration: 22) == .outsideWhatPlays)
    }

    /// A start at or past the end of the song has nothing to seek to.
    @Test
    func aStartPastTheEndIsNotInWhatPlays() {
        #expect(SectionStart.decide(start: 199.5, position: 0, duration: 200) == .outsideWhatPlays)
        #expect(SectionStart.decide(start: 250, position: 0, duration: 200) == .outsideWhatPlays)
    }
}
