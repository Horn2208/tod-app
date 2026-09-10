import Foundation
import Testing
@testable import TodApp

@Suite
struct HomeTodayTests {
    private let calendar = Calendar(identifier: .gregorian)
    /// Midday of a fixed day. Counting back from `Date()` made "five hours ago"
    /// land in yesterday whenever the suite ran before 05:00, which is now the
    /// difference between a post Home shows and one it hides.
    private let today = Calendar(identifier: .gregorian)
        .startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        .addingTimeInterval(12 * 3600)

    private func submission(_ id: Int, poster: String, minutesAgo: Int) -> Submission {
        Submission(
            id: id, posterID: poster, track: "Song \(id)", artist: "Wer auch immer",
            coverColorHex: "#000000", comments: [],
            postedAt: today.addingTimeInterval(Double(-minutesAgo * 60))
        )
    }

    private func group(_ submissions: [Submission], members: [Member] = []) -> Group {
        Group(id: "g", name: "Crew", icon: "🎵", members: members, roundEndsAt: today,
              submissions: submissions, chatMessages: [], activeBattle: nil)
    }

    private func mine(_ g: Group) -> Submission? {
        HomeToday.mySubmission(in: g, userID: "du", today: today, calendar: calendar)
    }

    @Test
    func withoutAPostThereIsNoSongToShow() {
        let g = group([submission(1, poster: "mats", minutesAgo: 30)])

        #expect(mine(g) == nil)
    }

    @Test
    func yourNewestPostIsTheOneHomeShows() {
        let g = group([
            submission(1, poster: "du", minutesAgo: 300),
            submission(2, poster: "du", minutesAgo: 20),
            submission(3, poster: "lena", minutesAgo: 5)
        ])

        #expect(mine(g)?.id == 2)
    }

    /// Home is about today's round. Yesterday's song must not stand in for one
    /// you have not posted -- the streak has already counted that day as
    /// missed, and the two would contradict each other on the same screen.
    @Test
    func yesterdaysPostIsNotShownAsTodays() {
        let g = group([submission(1, poster: "du", minutesAgo: 26 * 60)])

        #expect(mine(g) == nil)
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
