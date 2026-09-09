import Foundation
import Testing
@testable import TodApp

@Suite
struct GroupsFeedTests {
    private func member(_ id: String, posted: Bool = false) -> Member {
        Member(id: id, name: id.capitalized, isCurrentUser: id == "du",
               hasPostedToday: posted, postedDates: [])
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
              submissions: submissions, board: [], chatMessages: [], activeBattle: nil)
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
