import Foundation
import Testing
@testable import TodApp

@Suite
struct HomeTodayTests {
    private func submission(_ id: Int, poster: String, minutesAgo: Int) -> Submission {
        Submission(
            id: id, posterID: poster, track: "Song \(id)", artist: "Wer auch immer",
            coverColorHex: "#000000", comments: [],
            postedAt: Date().addingTimeInterval(Double(-minutesAgo * 60))
        )
    }

    private func group(_ submissions: [Submission], members: [Member] = []) -> Group {
        Group(id: "g", name: "Crew", icon: "🎵", members: members, roundEndsAt: .now,
              submissions: submissions, board: [], chatMessages: [], activeBattle: nil)
    }

    @Test
    func withoutAPostThereIsNoSongToShow() {
        let g = group([submission(1, poster: "mats", minutesAgo: 30)])

        let mine = HomeToday.mySubmission(in: g, userID: "du")

        #expect(mine == nil)
    }

    @Test
    func yourNewestPostIsTheOneHomeShows() {
        let g = group([
            submission(1, poster: "du", minutesAgo: 300),
            submission(2, poster: "du", minutesAgo: 20),
            submission(3, poster: "lena", minutesAgo: 5)
        ])

        let mine = HomeToday.mySubmission(in: g, userID: "du")

        #expect(mine?.id == 2)
    }

    @Test
    func meFindsTheCurrentUser() {
        let g = group([], members: [
            Member(id: "mats", name: "Mats", isCurrentUser: false, hasPostedToday: true, postedDates: []),
            Member(id: "du", name: "Du", isCurrentUser: true, hasPostedToday: false, postedDates: [])
        ])

        let me = HomeToday.me(in: g)

        #expect(me?.id == "du")
    }
}

@Suite
struct CoverColorTests {
    @Test
    func theSameTrackAlwaysGetsTheSameColour() {
        #expect(CoverColor.hex(forTrack: "abc") == CoverColor.hex(forTrack: "abc"))
    }

    /// The whole point: every posted song used to get one hard-coded pink, so
    /// the glow behind every card looked identical.
    @Test
    func differentTracksGetDifferentColours() {
        #expect(CoverColor.hex(forTrack: "abc") != CoverColor.hex(forTrack: "xyz"))
    }

    @Test
    func theResultIsAUsableHexColour() {
        let hex = CoverColor.hex(forTrack: "4cOdK2wGLETKBW3PvgPWqT")

        let onlyHexDigits = hex.dropFirst().allSatisfy(\.isHexDigit)

        #expect(hex.count == 7)
        #expect(hex.hasPrefix("#"))
        #expect(onlyHexDigits)
    }
}
