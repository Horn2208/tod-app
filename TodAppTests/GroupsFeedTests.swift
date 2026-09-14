import Foundation
import Testing
@testable import TodApp

@Suite
struct GroupsFeedTests {
    private func member(_ id: String, posted: Bool = false) -> Member {
        Member(id: id, name: id.capitalized, isCurrentUser: id == "du",
               postedDates: posted ? [Date()] : [])
    }

    private func submission(_ id: Int, _ track: String, minutesAgo: Int) -> Submission {
        Submission(
            id: id, posterID: "mats", track: track, artist: "Wer auch immer",
            coverColorHex: "#000000", comments: [],
            postedAt: Date().addingTimeInterval(Double(-minutesAgo * 60))
        )
    }

    private func group(_ id: String, _ name: String,
                       members: [Member] = [], submissions: [Submission] = []) -> Group {
        Group(id: id, name: name, icon: "🎵", members: members, roundEndsAt: .now,
              submissions: submissions, chatMessages: [], activeBattle: nil)
    }

    @Test
    func anEmptyQueryShowsEverything() {
        let groups = [group("a", "Late Night Crew"), group("b", "WG Chaos")]

        #expect(GroupsFeed.matching("   ", in: groups).count == 2)
    }

    @Test
    func theSearchIgnoresCapitals() {
        let groups = [group("a", "Late Night Crew"), group("b", "WG Chaos")]

        #expect(GroupsFeed.matching("wg", in: groups).map(\.id) == ["b"])
    }

    @Test
    func aQueryMatchingNothingShowsNothing() {
        let groups = [group("a", "Late Night Crew")]

        #expect(GroupsFeed.matching("Kegelclub", in: groups).isEmpty)
    }

    @Test
    func aGroupWithoutSongsSaysSoInsteadOfShowingAnEmptyLine() {
        #expect(GroupsFeed.previewText(for: group("a", "Leer")) == "Noch nichts gepostet")
    }

    @Test
    func thePreviewNamesTheNewestSong() {
        let g = group("a", "Crew", submissions: [
            submission(1, "Alt", minutesAgo: 300),
            submission(2, "Neu", minutesAgo: 10)
        ])

        #expect(GroupsFeed.previewText(for: g) == "Neu – Wer auch immer")
    }

    /// Someone in two groups is one person. Two circles would read as two.
    @Test
    func aMemberInTwoGroupsAppearsOnce() {
        let groups = [
            group("a", "Eins", members: [member("mats"), member("lena")]),
            group("b", "Zwei", members: [member("mats"), member("jaro")])
        ]

        #expect(GroupsFeed.storyMembers(across: groups).map(\.id).sorted() == ["jaro", "lena", "mats"])
    }

    /// You are the one person guaranteed to be looking for yourself.
    @Test
    func youComeFirstEvenWithoutHavingPostedYet() {
        let groups = [group("a", "Eins", members: [
            member("mats", posted: true), member("du")
        ])]

        #expect(GroupsFeed.storyMembers(across: groups).first?.id == "du")
    }

    /// Posting in one of your groups counts even if the dedup happens to meet
    /// you there second: the ring answers "did they post today", not "did
    /// they post in the group that was scanned first".
    @Test
    func postingInEitherGroupEarnsTheRing() {
        let groups = [
            group("a", "Eins", members: [member("mats", posted: false)]),
            group("b", "Zwei", members: [member("mats", posted: true)])
        ]

        #expect(GroupsFeed.storyMembers(across: groups).first { $0.id == "mats" }?.hasPostedToday == true)
    }

    @Test
    func whoeverPostedTodayComesFirst() {
        let groups = [group("a", "Eins", members: [
            member("lena"), member("mats", posted: true)
        ])]

        #expect(GroupsFeed.storyMembers(across: groups).first?.id == "mats")
    }

    @Test
    func theGroupWithTheNewestSongComesFirst() {
        let groups = [
            group("a", "Alt", submissions: [submission(1, "X", minutesAgo: 500)]),
            group("b", "Neu", submissions: [submission(2, "Y", minutesAgo: 5)])
        ]

        #expect(GroupsFeed.ordered(groups).map(\.id) == ["b", "a"])
    }

    /// A group nobody has posted to has no date to sort by; it belongs at the
    /// bottom rather than at the top by accident.
    @Test
    func aGroupWithoutSongsSinksToTheBottom() {
        let groups = [
            group("a", "Leer"),
            group("b", "Voll", submissions: [submission(1, "X", minutesAgo: 100)])
        ]

        #expect(GroupsFeed.ordered(groups).map(\.id) == ["b", "a"])
    }
}

/// Where a tap on someone in the story row leads, and what their bubble says.
/// Fixed dates in a fixed zone: "today" measured against the real clock would
/// flip at midnight, halfway through a run.
@Suite
struct StoryRowTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    private var today: Date { at(day: 14, hour: 12) }

    private func at(day: Int, hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
    }

    private let mats = Member(id: "mats", name: "Mats", isCurrentUser: false, postedDates: [])

    private func song(_ id: Int, by poster: String = "mats", on date: Date) -> Submission {
        Submission(
            id: id, posterID: poster, track: "Blinding Lights", artist: "The Weeknd",
            coverColorHex: "#000000", comments: [], postedAt: date)
    }

    private func group(_ id: String, _ submissions: [Submission]) -> Group {
        Group(id: id, name: id, icon: "🎵", members: [mats], roundEndsAt: .now,
              submissions: submissions, chatMessages: [], activeBattle: nil)
    }

    private func target(_ groups: [Group]) -> GroupsFeed.StoryTarget? {
        GroupsFeed.storyTarget(for: mats, in: groups, today: today, calendar: calendar)
    }

    private func bubble(_ groups: [Group]) -> GroupsFeed.StoryBubble? {
        GroupsFeed.storyBubble(for: mats, in: groups, today: today, calendar: calendar)
    }

    @Test
    func todaysSongOpensTheRunningFeedAtItsCard() {
        #expect(target([group("lnc", [song(1, on: at(day: 14, hour: 9))])])
                == .today(groupID: "lnc", submissionID: 1))
    }

    @Test
    func yesterdaysSongOpensTheRevealAtItsCard() {
        #expect(target([group("lnc", [song(2, on: at(day: 13, hour: 20))])])
                == .yesterday(groupID: "lnc", submissionID: 2))
    }

    /// Two days back is in no round on screen any more.
    @Test
    func anOlderSongOpensOnItsOwn() {
        #expect(target([group("lnc", [song(3, on: at(day: 11, hour: 20))])]) == .older(submissionID: 3))
    }

    @Test
    func someoneWhoNeverPostedLeadsNowhere() {
        #expect(target([group("lnc", [song(4, by: "lena", on: at(day: 14, hour: 9))])]) == nil)
    }

    /// The row spans every group, the feed shows one: it has to be the group
    /// of the newest post, not whichever group happens to come first.
    @Test
    func theNewestPostAcrossGroupsDecidesWhichFeedOpens() {
        let groups = [
            group("lnc", [song(5, on: at(day: 13, hour: 20))]),
            group("wg", [song(6, on: at(day: 14, hour: 8))]),
        ]

        #expect(target(groups) == .today(groupID: "wg", submissionID: 6))
    }

    @Test
    func theBubbleShowsTodaysSong() {
        #expect(bubble([group("lnc", [song(7, on: at(day: 14, hour: 9))])])
                == GroupsFeed.StoryBubble(track: "Blinding Lights", artist: "The Weeknd"))
    }

    /// The bubble is about today, like the ring.
    @Test
    func yesterdaysSongEarnsNoBubble() {
        #expect(bubble([group("lnc", [song(8, on: at(day: 13, hour: 22))])]) == nil)
    }
}

@Suite
struct FeedOrderTests {
    private func song(_ id: Int) -> Submission {
        Submission(
            id: id, posterID: "mats", track: "Song \(id)", artist: "Wer auch immer",
            coverColorHex: "#000000", comments: [], postedAt: .now)
    }

    @Test
    func theChosenCardComesFirstAndTheRestKeepTheirOrder() {
        let ordered = GroupsFeed.feedOrder([song(1), song(2), song(3), song(4)], startingAt: 3)

        #expect(ordered.map(\.id) == [3, 1, 2, 4])
    }

    @Test
    func withoutAChosenCardNothingMoves() {
        #expect(GroupsFeed.feedOrder([song(1), song(2)], startingAt: nil).map(\.id) == [1, 2])
    }

    /// A song no longer in the round -- the day turned over while the row was
    /// on screen -- changes nothing rather than emptying the feed.
    @Test
    func aCardNotInTheRoundChangesNothing() {
        #expect(GroupsFeed.feedOrder([song(1), song(2)], startingAt: 9).map(\.id) == [1, 2])
    }
}
