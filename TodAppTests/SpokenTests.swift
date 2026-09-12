import Foundation
import Testing
@testable import TodApp

@Suite
struct SpokenTests {
    @Test
    func timeReadsAsMinutesAndSeconds() {
        #expect(Spoken.time(0) == "0:00")
        #expect(Spoken.time(65) == "1:05")
        #expect(Spoken.time(3599) == "59:59")
    }

    /// A player that has not started reports a position of zero -- or, on a
    /// bad frame, a hair below it. "-0:-1" is not a time.
    @Test
    func aNegativePositionIsStillZero() {
        #expect(Spoken.time(-0.4) == "0:00")
    }

    @Test
    func aSongIsOneSentence() {
        #expect(Spoken.song(track: "Nights", artist: "Frank Ocean") == "Nights von Frank Ocean")
    }

    /// A link posted without metadata has no artist to name.
    @Test
    func aSongWithoutAnArtistIsJustItsTitle() {
        #expect(Spoken.song(track: "Nights", artist: "") == "Nights")
    }

    @Test
    func playbackSaysHowFarAlongItIs() {
        #expect(Spoken.playback(position: 63, duration: 200) == "1:03 von 3:20")
    }

    /// Before anything has said how long the track is, "von 0:00" would be a
    /// number nobody can use.
    @Test
    func playbackWithoutALengthSaysOnlyThePosition() {
        #expect(Spoken.playback(position: 63, duration: 0) == "1:03")
    }

    @Test
    func theStoryRowSaysWhoHasPostedToday() {
        #expect(Spoken.storyMember(name: "Mats", isCurrentUser: false, hasPostedToday: true)
                == "Mats, hat heute gepostet")
        #expect(Spoken.storyMember(name: "Mats", isCurrentUser: false, hasPostedToday: false)
                == "Mats, heute noch nichts")
    }

    /// The row calls the current user "Du", the same way the screen does.
    @Test
    func theCurrentUserIsAddressedAsDu() {
        #expect(Spoken.storyMember(name: "Lennet", isCurrentUser: true, hasPostedToday: true)
                == "Du, hat heute gepostet")
    }

    @Test
    func aGroupRowIsNameThenNewsThenTime() {
        #expect(Spoken.groupRow(name: "LNC", preview: "Genesis – Justice", time: "12:39")
                == "LNC, Genesis – Justice, 12:39")
    }

    /// A group nobody has posted in has no time to read out.
    @Test
    func aGroupRowWithoutATimeStopsAfterTheNews() {
        #expect(Spoken.groupRow(name: "LNC", preview: "noch nichts heute", time: nil)
                == "LNC, noch nichts heute")
    }
}
