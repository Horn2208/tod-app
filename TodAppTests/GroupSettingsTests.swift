import Foundation
import Testing
@testable import TodApp

private func member(_ id: String) -> Member {
    Member(id: id, name: id.capitalized, isCurrentUser: id == "du",
           hasPostedToday: false, postedDates: [])
}

private func makeGroup(
    creator: String = "lena",
    policy: InvitePolicy = .everyone,
    members: [String] = ["du", "lena", "mats"],
    submissions: [Submission] = []
) -> Group {
    Group(
        id: "g", name: "Crew", icon: "🎵", members: members.map(member),
        roundEndsAt: .now, submissions: submissions, board: [], chatMessages: [],
        activeBattle: nil, creatorID: creator, invitePolicy: policy
    )
}

@Suite
struct GroupPermissionTests {
    @Test
    func onAnOpenGroupEveryMemberMayInvite() {
        let group = makeGroup(policy: .everyone)

        #expect(GroupPermissions.mayInvite("du", to: group))
        #expect(GroupPermissions.mayInvite("lena", to: group))
    }

    /// "Everyone" means everyone *in* the group, not everyone at all.
    @Test
    func someoneOutsideTheGroupNeverMayInvite() {
        #expect(GroupPermissions.mayInvite("fremd", to: makeGroup(policy: .everyone)) == false)
    }

    @Test
    func whenItIsTheCreatorsToGiveNobodyElseMayInvite() {
        let group = makeGroup(creator: "lena", policy: .creatorOnly)

        #expect(GroupPermissions.mayInvite("lena", to: group))
        #expect(GroupPermissions.mayInvite("du", to: group) == false)
    }

    /// The lever itself. If anyone could move it, being locked out would mean
    /// nothing -- unlock yourself, then invite.
    @Test
    func onlyTheCreatorMovesTheInviteSetting() {
        let group = makeGroup(creator: "lena", policy: .creatorOnly)

        #expect(GroupPermissions.mayChangeInvitePolicy("lena", of: group))
        #expect(GroupPermissions.mayChangeInvitePolicy("du", of: group) == false)
    }
}

@Suite
struct SeasonScoreTests {
    private func submission(_ id: Int, by poster: String) -> Submission {
        Submission(id: id, posterID: poster, track: "S\(id)", artist: "A",
                   coverColorHex: "#000000", comments: [])
    }

    @Test
    func aMembersPointsAreTheSumOfTheirOwnSongs() {
        let totals = SeasonScore.totals(
            members: [member("du"), member("lena")],
            submissions: [submission(1, by: "du"), submission(2, by: "du"), submission(3, by: "lena")],
            scores: [
                RoundScore(submissionID: 1, points: 4, hiddenGemCount: 0),
                RoundScore(submissionID: 2, points: -1, hiddenGemCount: 0),
                RoundScore(submissionID: 3, points: 5, hiddenGemCount: 0)
            ]
        )

        #expect(totals.first { $0.memberID == "du" }?.points == 3)
        #expect(totals.first { $0.memberID == "lena" }?.points == 5)
    }

    @Test
    func theTableIsOrderedByPoints() {
        let totals = SeasonScore.totals(
            members: [member("du"), member("lena")],
            submissions: [submission(1, by: "du"), submission(2, by: "lena")],
            scores: [
                RoundScore(submissionID: 1, points: 1, hiddenGemCount: 0),
                RoundScore(submissionID: 2, points: 9, hiddenGemCount: 0)
            ]
        )

        #expect(totals.map(\.memberID) == ["lena", "du"])
    }

    /// A group's table lists the group. Someone who has never posted belongs
    /// in it on zero, not left out of their own group's standings.
    @Test
    func aMemberWhoNeverPostedStillAppears() {
        let totals = SeasonScore.totals(
            members: [member("du"), member("sude")],
            submissions: [submission(1, by: "du")],
            scores: [RoundScore(submissionID: 1, points: 2, hiddenGemCount: 0)]
        )

        let sude = totals.first { $0.memberID == "sude" }
        #expect(sude?.points == 0)
        #expect(sude?.roundsPlayed == 0)
    }

    /// Zero from six rounds is not the same as zero from none, so only songs
    /// that actually have a score are counted as rounds played.
    @Test
    func aSongWithoutAScoreIsNotARoundPlayed() {
        let totals = SeasonScore.totals(
            members: [member("du")],
            submissions: [submission(1, by: "du"), submission(2, by: "du")],
            scores: [RoundScore(submissionID: 1, points: 0, hiddenGemCount: 0)]
        )

        #expect(totals.first?.points == 0)
        #expect(totals.first?.roundsPlayed == 1)
    }
}

@Suite
struct GroupEditingTests {
    @Test
    func renamingAGroupSticks() async throws {
        let repo = InMemoryRepository()

        try await repo.updateGroup(id: "wg", name: "WG Ordnung", imageData: nil, invitePolicy: .everyone)

        #expect(try await repo.fetchGroup(id: "wg").name == "WG Ordnung")
    }

    @Test
    func aBlankNameLeavesTheOldOne() async throws {
        let repo = InMemoryRepository()
        let before = try await repo.fetchGroup(id: "wg").name

        try await repo.updateGroup(id: "wg", name: "   ", imageData: nil, invitePolicy: .everyone)

        #expect(try await repo.fetchGroup(id: "wg").name == before)
    }

    /// Nil means "leave the picture alone", not "remove it" -- the settings
    /// screen edits name and picture independently.
    @Test
    func renamingKeepsThePicture() async throws {
        let repo = InMemoryRepository()
        let picture = Data([0x09])
        try await repo.updateGroup(id: "wg", name: "A", imageData: picture, invitePolicy: .everyone)

        try await repo.updateGroup(id: "wg", name: "B", imageData: nil, invitePolicy: .everyone)

        let group = try await repo.fetchGroup(id: "wg")
        #expect(group.imageData == picture)
        #expect(group.name == "B")
    }

    @Test
    func aMemberCanBeAddedToAnOpenGroup() async throws {
        let repo = InMemoryRepository()

        try await repo.addMember(named: "Kim", to: "wg", asking: "du")

        #expect(try await repo.fetchGroup(id: "wg").members.contains { $0.name == "Kim" })
    }

    /// The permission is enforced where the write happens, not only where the
    /// button is -- `lnc` is seeded as Lena's, invites hers alone.
    @Test
    func aClosedGroupRefusesAnInviteFromSomeoneElse() async throws {
        let repo = InMemoryRepository()

        await #expect(throws: TodAppError.notAllowed) {
            try await repo.addMember(named: "Kim", to: "lnc", asking: "du")
        }
    }

    @Test
    func theCreatorOfAClosedGroupMayStillInvite() async throws {
        let repo = InMemoryRepository()

        try await repo.addMember(named: "Kim", to: "lnc", asking: "lena")

        #expect(try await repo.fetchGroup(id: "lnc").members.contains { $0.name == "Kim" })
    }

    /// Two people with the same name are two members, not one.
    @Test
    func twoMembersWithTheSameNameGetDifferentIDs() async throws {
        let repo = InMemoryRepository()

        try await repo.addMember(named: "Kim", to: "wg", asking: "du")
        try await repo.addMember(named: "Kim", to: "wg", asking: "du")

        let kims = try await repo.fetchGroup(id: "wg").members.filter { $0.name == "Kim" }
        #expect(kims.count == 2)
        #expect(Set(kims.map(\.id)).count == 2)
    }
}

@Suite
@MainActor
struct GroupSettingsStoreTests {
    private func makeStore() async -> AppStore {
        let repo = InMemoryRepository()
        let store = AppStore(
            groupRepo: repo, submissionRepo: repo, voteRepo: repo,
            leaderboardRepo: repo, chatRepo: repo, battleRepo: repo
        )
        await store.loadGroups()
        return store
    }

    /// The store guards the lever as well as the picker does: reaching this
    /// call from anywhere else must not hand out the permission.
    @Test
    func someoneWhoDidNotCreateTheGroupCannotOpenItUp() async {
        let store = await makeStore()
        store.selectGroup("lnc")

        await store.updateGroup(name: "Late Night Crew", imageData: nil, invitePolicy: .everyone)

        #expect(store.currentGroup?.invitePolicy == .creatorOnly)
        #expect(store.mayInvite == false)
    }

    @Test
    func theCreatorCanCloseTheirOwnGroup() async {
        let store = await makeStore()
        store.selectGroup("wg")

        await store.updateGroup(name: "WG Chaos", imageData: nil, invitePolicy: .creatorOnly)

        #expect(store.currentGroup?.invitePolicy == .creatorOnly)
        // Still theirs to invite into -- the creator is never locked out.
        #expect(store.mayInvite)
    }

    /// The season counts revealed rounds only. Yesterday's is seeded with
    /// votes; today's is deliberately unvoted and must not appear.
    @Test
    func theSeasonTableCountsOnlyRevealedRounds() async {
        let store = await makeStore()
        store.selectGroup("lnc")

        await store.loadSeasonTotals()

        let lena = store.seasonTotals.first { $0.memberID == "lena" }
        let mats = store.seasonTotals.first { $0.memberID == "mats" }
        #expect(lena?.points == 5)   // "Nights", yesterday
        #expect(mats?.points == 4)   // "Redbone", yesterday
        #expect(lena?.roundsPlayed == 1)
        #expect(store.seasonTotals.map(\.memberID).contains("sude"))
    }
}

@Suite
struct RevealedVoteTests {
    /// The reveal shows who said what -- a score cannot carry a note.
    @Test
    func aRevealedRoundHandsBackEveryVoteWithItsReason() async throws {
        let repo = InMemoryRepository()

        let votes = try await repo.fetchVotes(groupID: "lnc", day: RoundVisibility.revealedDay())

        #expect(votes.count == 12)
        let dusVote = votes.first { $0.voterID == "du" && $0.submissionID == 9 }
        #expect(dusVote?.rating == .banger)
        #expect(dusVote?.note == "die zweite Hälfte ist ein anderer Song")
    }

    /// Today's votes are nobody's business, so asking for another day gives
    /// only that day -- the running round never leaks in.
    @Test
    func todaysVotesAreNotInYesterdaysRound() async throws {
        let repo = InMemoryRepository()
        try await repo.castVote(
            Vote(voterID: "du", submissionID: 1, rating: .banger, isHiddenGem: false, note: "heute"),
            groupID: "lnc")

        let revealed = try await repo.fetchVotes(groupID: "lnc", day: RoundVisibility.revealedDay())

        #expect(revealed.contains { $0.submissionID == 1 } == false)
    }

    /// Your own note comes back for the round you ask about, so today's screen
    /// shows what you wrote today and nothing older.
    @Test
    func yourOwnNotesComeBackPerRound() async throws {
        let repo = InMemoryRepository()

        let revealed = try await repo.fetchMyVotes(
            voterID: "du", groupID: "lnc", day: RoundVisibility.revealedDay())
        let today = try await repo.fetchMyVotes(voterID: "du", groupID: "lnc", day: Date())

        #expect(revealed.notes[9] == "die zweite Hälfte ist ein anderer Song")
        #expect(today.notes.isEmpty)
    }
}
