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
            Member(id: "mats", name: "Mats", isCurrentUser: false, postedDates: []),
            Member(id: "du", name: "Du", isCurrentUser: true, postedDates: [])
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

/// The group's round under one's own song.
@Suite
struct HomeRoundStatusTests {
    private let noon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!

    private func member(_ id: String) -> Member {
        Member(id: id, name: id, isCurrentUser: id == "me", postedDates: [])
    }

    private func song(_ id: Int, by poster: String, daysAgo: Int = 0) -> Submission {
        Submission(
            id: id, posterID: poster, track: "T\(id)", artist: "A", coverColorHex: "#222222",
            comments: [], postedAt: noon.addingTimeInterval(Double(-daysAgo) * 86_400 - 3_600))
    }

    private func group(_ songs: [Submission]) -> Group {
        Group(
            id: "g", name: "WG", icon: "🎧",
            members: ["me", "lena", "max", "tim", "nora"].map(member),
            roundEndsAt: noon, submissions: songs, chatMessages: [], activeBattle: nil)
    }

    @Test
    func countsWhoPostedAndWhatIsLeftToRate() {
        let status = HomeToday.status(
            in: group([song(1, by: "me"), song(2, by: "lena"), song(3, by: "max")]),
            userID: "me", rated: [2], now: noon)
        #expect(status.posted == 3)
        #expect(status.members == 5)
        #expect(status.toRate == 1)
        #expect(status.others == 2)
    }

    @Test
    func yesterdaysSongsCountAsRevealedNotAsToday() {
        let status = HomeToday.status(
            in: group([song(1, by: "lena", daysAgo: 1)]), userID: "me", rated: [], now: noon)
        #expect(status.posted == 0)
        #expect(status.revealed == 1)
    }

    @Test
    func theLineSaysItInOneSentence() {
        let status = HomeToday.RoundStatus(posted: 3, members: 5, toRate: 2, others: 2, revealIn: 6 * 3_600 - 60, revealed: 0)
        #expect(HomeToday.line(status) == "3 von 5 haben gepostet · 2 Songs zu bewerten · Aufdeckung in 6 Std.")
    }

    @Test
    func allRatedAndTheLastHour() {
        let status = HomeToday.RoundStatus(posted: 1, members: 2, toRate: 0, others: 1, revealIn: 25 * 60, revealed: 0)
        #expect(HomeToday.line(status) == "1 von 2 hat gepostet · alles bewertet · Aufdeckung in 25 Min.")
    }
}
