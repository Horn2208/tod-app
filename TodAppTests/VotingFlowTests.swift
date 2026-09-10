import Foundation
import Testing
@testable import TodApp

/// Records votes in memory so the store's behaviour can be observed without
/// the shared singleton, which other suites also touch.
actor MockVoteRepository: VoteRepository {
    /// Keyed by the three fields rather than a glued string, so a test can tell
    /// group scoping apart -- reading votes back without the group made every
    /// store-level test pass even if `AppStore` stopped scoping at all.
    private struct Key: Hashable {
        let voterID: String
        let submissionID: Int
        let groupID: String
    }

    private var votes: [Key: Vote] = [:]
    private var hiddenGem: [String: Int] = [:]
    private(set) var roundScores: [RoundScore] = []
    /// Submissions this repository refuses to record a vote for, standing in
    /// for a round whose day ended while the screen was still showing it.
    private let closedSubmissions: Set<Int>

    init(roundScores: [RoundScore] = [], closedSubmissions: Set<Int> = []) {
        self.roundScores = roundScores
        self.closedSubmissions = closedSubmissions
    }

    func castVote(_ vote: Vote, groupID: String) async throws {
        guard !closedSubmissions.contains(vote.submissionID) else { throw TodAppError.roundClosed }
        votes[Key(voterID: vote.voterID, submissionID: vote.submissionID, groupID: groupID)] = vote
    }

    func setHiddenGem(submissionID: Int, voterID: String, groupID: String) async throws {
        guard !closedSubmissions.contains(submissionID) else { throw TodAppError.roundClosed }
        let key = "\(voterID)-\(groupID)"
        hiddenGem[key] = hiddenGem[key] == submissionID ? nil : submissionID
    }

    func fetchMyVotes(voterID: String, groupID: String, day: Date) async throws -> MyVotes {
        var ratings: [Int: Rating] = [:]
        for (key, vote) in votes where key.voterID == voterID && key.groupID == groupID {
            ratings[key.submissionID] = vote.rating
        }
        var notes: [Int: String] = [:]
        for (key, vote) in votes where key.voterID == voterID && key.groupID == groupID {
            if let note = vote.note { notes[key.submissionID] = note }
        }
        return MyVotes(
            ratings: ratings, notes: notes, hiddenGemID: hiddenGem["\(voterID)-\(groupID)"]
        )
    }

    func fetchRoundScores(groupID: String, day: Date) async throws -> [RoundScore] {
        roundScores
    }

    func fetchRevealedScores(groupID: String) async throws -> [RoundScore] {
        roundScores
    }

    func fetchVotes(groupID: String, day: Date) async throws -> [Vote] {
        votes.values.filter { $0.voterID.isEmpty == false }
    }
}

/// Yesterday, by the calendar rather than by subtracting hours: just after
/// midnight, "24 hours ago" is still yesterday but "26 hours ago" is not, and a
/// suite that runs at 01:00 would be testing the arithmetic instead of the rule.
private var yesterday: Date {
    Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
}

private func makeGroup(id: String = "test") -> Group {
    Group(
        id: id, name: "Test", icon: "🧪",
        members: [Member(id: "du", name: "Du", isCurrentUser: true, hasPostedToday: true, postedDates: [.now])],
        roundEndsAt: .now,
        submissions: [
            Submission(id: 1, posterID: "mats", track: "A", artist: "X", coverColorHex: "#111111", comments: [], postedAt: .now),
            Submission(id: 2, posterID: "lena", track: "B", artist: "Y", coverColorHex: "#222222", comments: [], postedAt: .now),
            Submission(id: 3, posterID: "du", track: "C", artist: "Z", coverColorHex: "#333333", comments: [], postedAt: .now),
            // Yesterday's round: decided, revealed, and off the voting screen.
            Submission(id: 4, posterID: "mats", track: "D", artist: "W", coverColorHex: "#444444", comments: [], postedAt: yesterday)
        ],
        board: [], chatMessages: [], activeBattle: nil
    )
}

@Suite
@MainActor
struct VotingFlowTests {
    private func makeStore(_ votes: MockVoteRepository) async -> AppStore {
        let store = AppStore(
            groupRepo: MockGroupRepository(groups: [makeGroup(), makeGroup(id: "other")]),
            voteRepo: votes
        )
        await store.loadGroups()
        store.selectGroup("test")
        await store.loadMyVotes()
        return store
    }

    @Test
    func ratingATrackIsRememberedByTheStore() async {
        let store = await makeStore(MockVoteRepository())

        await store.castVote(.banger, for: 1)

        #expect(store.myVotes.ratings[1] == .banger)
    }

    @Test
    func theHiddenGemTogglesOffWhenTappedTwice() async {
        let store = await makeStore(MockVoteRepository())

        await store.toggleHiddenGem(2)
        #expect(store.myVotes.hiddenGemID == 2)

        await store.toggleHiddenGem(2)
        #expect(store.myVotes.hiddenGemID == nil)
    }

    /// What withholding the result buys: while the day runs there is nothing to
    /// give away, so a change of mind costs nothing and is simply allowed.
    @Test
    func aRatingCanBeChangedForAsLongAsTheDayRuns() async {
        let store = await makeStore(MockVoteRepository())

        await store.castVote(.banger, for: 1)
        await store.castVote(.awful, for: 1)

        #expect(store.myVotes.ratings[1] == .awful)
        #expect(store.lastError == nil)
    }

    /// The scores on screen are the revealed round's, and they arrive with the
    /// votes -- there is no longer a button whose press fetches them.
    @Test
    func loadingVotesAlsoBringsTheRevealedRoundsScores() async {
        let repo = MockVoteRepository(roundScores: [
            RoundScore(submissionID: 1, points: 3, hiddenGemCount: 1),
            RoundScore(submissionID: 2, points: -1, hiddenGemCount: 0)
        ])

        let store = await makeStore(repo)

        #expect(store.roundScores.map(\.submissionID) == [1, 2])
        #expect(store.lastError == nil)
    }

    /// The rule the redesign turns on: yesterday's round is decided, and the
    /// store refuses it before the repository is ever asked.
    @Test
    func yesterdaysSongCanNoLongerBeRated() async {
        let store = await makeStore(MockVoteRepository())

        await store.castVote(.banger, for: 4)

        #expect(store.myVotes.ratings[4] == nil)
        #expect(store.lastError == nil)
    }

    @Test
    func yesterdaysSongCanNoLongerBecomeYourHiddenGem() async {
        let store = await makeStore(MockVoteRepository())

        await store.toggleHiddenGem(4)

        #expect(store.myVotes.hiddenGemID == nil)
        #expect(store.lastError == nil)
    }

    /// A round that closed between the screen drawing and the tap landing is an
    /// expected dead end, not a failure to shout about -- the repository
    /// throws, and the store must swallow it.
    @Test
    func aVoteArrivingAfterTheRoundClosedDoesNotRaiseAnError() async {
        let store = await makeStore(MockVoteRepository(closedSubmissions: [1]))

        await store.castVote(.awful, for: 1)

        #expect(store.lastError == nil)
        #expect(store.myVotes.ratings[1] == nil)
    }

    @Test
    func yourOwnSongCannotBeRated() async {
        let store = await makeStore(MockVoteRepository())

        await store.castVote(.banger, for: 3)

        #expect(store.myVotes.ratings[3] == nil)
        #expect(store.lastError == nil)
    }

    @Test
    func yourOwnSongCannotBeYourHiddenGem() async {
        let store = await makeStore(MockVoteRepository())

        await store.toggleHiddenGem(3)

        #expect(store.myVotes.hiddenGemID == nil)
        #expect(store.lastError == nil)
    }

    /// The voting screen is today's round: your own song stays in it so the
    /// round keeps its real size, and yesterday's is gone from both lists.
    @Test
    func theVotingScreenShowsTodaysRoundWithoutYourOwnSongToJudge() async {
        let store = await makeStore(MockVoteRepository())

        #expect(store.currentGroup?.submissions.count == 4)
        #expect(store.runningSubmissions.map(\.id) == [1, 2, 3])
        #expect(store.votableSubmissions.map(\.id) == [1, 2])
    }

    /// Reveal is the other half of the same split: yesterday's round, and only
    /// that one.
    @Test
    func revealShowsYesterdaysRoundAlone() async {
        let store = await makeStore(MockVoteRepository())

        #expect(store.revealedSubmissions.map(\.id) == [4])
    }

    /// A round belongs to its group. Switching groups must show that group's
    /// votes, not whatever was rated last.
    @Test
    func votesFromOneGroupDoNotAppearInAnother() async {
        let store = await makeStore(MockVoteRepository())
        await store.castVote(.banger, for: 1)

        store.selectGroup("other")
        await store.loadMyVotes()

        #expect(store.myVotes.ratings.isEmpty)
    }

    /// A rating may carry a reason, and the two travel together as one vote.
    @Test
    func aReasonIsKeptBesideTheRating() async {
        let store = await makeStore(MockVoteRepository())

        await store.castVote(.banger, for: 1, note: "der Beat-Switch")

        #expect(store.myVotes.ratings[1] == .banger)
        #expect(store.myVotes.notes[1] == "der Beat-Switch")
    }

    /// Whitespace is not a reason. Storing it would put an empty line under a
    /// rating in the reveal.
    @Test
    func aBlankReasonIsNotKept() async {
        let store = await makeStore(MockVoteRepository())

        await store.castVote(.good, for: 1, note: "   ")

        #expect(store.myVotes.ratings[1] == .good)
        #expect(store.myVotes.notes[1] == nil)
    }

    @Test
    func changingYourMindReplacesTheReasonToo() async {
        let store = await makeStore(MockVoteRepository())
        await store.castVote(.banger, for: 1, note: "erst gut")

        await store.castVote(.awful, for: 1, note: "dann doch nicht")

        #expect(store.myVotes.ratings[1] == .awful)
        #expect(store.myVotes.notes[1] == "dann doch nicht")
    }

    @Test
    func reopeningTheAppRestoresVotesAlreadyCast() async {
        let repo = MockVoteRepository()
        let first = await makeStore(repo)
        await first.castVote(.meh, for: 2)

        let second = await makeStore(repo)

        #expect(second.myVotes.ratings[2] == .meh)
    }
}

@Suite
struct RoundScoringTests {
    @Test
    func scoresSumEveryVotersRatingPerSubmission() async throws {
        let repo = InMemoryRepository()
        try await repo.castVote(
            Vote(voterID: "du", submissionID: 1, rating: .banger, isHiddenGem: false), groupID: "lnc")
        try await repo.castVote(
            Vote(voterID: "mats", submissionID: 1, rating: .good, isHiddenGem: false), groupID: "lnc")
        try await repo.castVote(
            Vote(voterID: "lena", submissionID: 2, rating: .awful, isHiddenGem: false), groupID: "lnc")

        let scores = try await repo.fetchRoundScores(groupID: "lnc", day: Date())

        #expect(scores.first { $0.submissionID == 1 }?.points == 3)   // 2 + 1
        #expect(scores.first { $0.submissionID == 2 }?.points == -2)
    }

    @Test
    func aSubmissionNobodyRatedScoresZeroRatherThanVanishing() async throws {
        let repo = InMemoryRepository()
        let group = try await repo.fetchGroup(id: "lnc")
        let running = RoundVisibility.runningSubmissions(from: group.submissions)

        let scores = try await repo.fetchRoundScores(groupID: "lnc", day: Date())

        #expect(scores.count == running.count)
        #expect(scores.allSatisfy { $0.points == 0 })
    }

    @Test
    func hiddenGemsAreCountedButDoNotChangeThePoints() async throws {
        let repo = InMemoryRepository()
        try await repo.castVote(
            Vote(voterID: "du", submissionID: 1, rating: .ok, isHiddenGem: false), groupID: "lnc")
        try await repo.setHiddenGem(submissionID: 1, voterID: "du", groupID: "lnc")

        let scores = try await repo.fetchRoundScores(groupID: "lnc", day: Date())
        let first = try #require(scores.first { $0.submissionID == 1 })

        #expect(first.hiddenGemCount == 1)
        #expect(first.points == 0)  // .ok is worth nothing on its own
    }

    /// The rule where the write happens, not only where the buttons are: a
    /// caller that got past the screen still cannot change a decided round.
    @Test
    func votingIsRefusedOnceTheRoundIsRevealed() async throws {
        let repo = InMemoryRepository()

        await #expect(throws: TodAppError.roundClosed) {
            try await repo.castVote(
                Vote(voterID: "du", submissionID: 8, rating: .good, isHiddenGem: false), groupID: "lnc")
        }
    }

    /// A round is one day, so a score is one day's -- not a sum over every song
    /// the group has ever posted.
    @Test
    func aRoundIsScoredOverItsOwnDayOnly() async throws {
        let repo = InMemoryRepository()

        let scores = try await repo.fetchRoundScores(
            groupID: "lnc", day: RoundVisibility.revealedDay())

        #expect(scores.map(\.submissionID).sorted() == [8, 9, 10])
        #expect(scores.first { $0.submissionID == 9 }?.points == 5)
        #expect(scores.leaders.map(\.submissionID) == [9])
    }

    /// One gem per round, not one per group. Setting today's used to move the
    /// single stored gem, quietly rewriting a round whose scores were already
    /// out.
    @Test
    func todaysHiddenGemDoesNotMoveYesterdays() async throws {
        let repo = InMemoryRepository()

        try await repo.setHiddenGem(submissionID: 1, voterID: "du", groupID: "lnc")

        let revealed = try await repo.fetchRoundScores(
            groupID: "lnc", day: RoundVisibility.revealedDay())
        #expect(revealed.first { $0.submissionID == 9 }?.hiddenGemCount == 1)
    }

    /// Your own votes come back for the round you ask about, so today's screen
    /// never shows a rating you gave yesterday.
    @Test
    func yourVotesComeBackPerRound() async throws {
        let repo = InMemoryRepository()
        try await repo.castVote(
            Vote(voterID: "du", submissionID: 1, rating: .good, isHiddenGem: false), groupID: "lnc")

        let today = try await repo.fetchMyVotes(voterID: "du", groupID: "lnc", day: Date())
        let revealed = try await repo.fetchMyVotes(
            voterID: "du", groupID: "lnc", day: RoundVisibility.revealedDay())

        #expect(today.ratings[1] == .good)
        #expect(today.ratings[9] == nil)
        #expect(revealed.ratings[9] == .banger)
        #expect(revealed.hiddenGemID == 9)
    }
}

/// `leaders` is what Reveal crowns, so its edge cases are worth pinning down:
/// nobody voted, everybody tied, and a round that only went negative.
@Suite
struct RoundLeaderTests {
    @Test
    func theHighestScoringSubmissionLeadsAlone() {
        let scores = [
            RoundScore(submissionID: 1, points: 3, hiddenGemCount: 0),
            RoundScore(submissionID: 2, points: 1, hiddenGemCount: 2)
        ]

        #expect(scores.leaders.map(\.submissionID) == [1])
    }

    @Test
    func aTieCrownsEveryTiedSubmission() {
        let scores = [
            RoundScore(submissionID: 1, points: 2, hiddenGemCount: 0),
            RoundScore(submissionID: 2, points: 2, hiddenGemCount: 0),
            RoundScore(submissionID: 3, points: 1, hiddenGemCount: 0)
        ]

        #expect(scores.leaders.map(\.submissionID) == [1, 2])
    }

    @Test
    func aRoundNobodyRatedHasNoLeader() {
        let scores = [
            RoundScore(submissionID: 1, points: 0, hiddenGemCount: 0),
            RoundScore(submissionID: 2, points: 0, hiddenGemCount: 1)
        ]

        #expect(scores.leaders.isEmpty)
    }

    @Test
    func aRoundEverybodyDislikedHasNoLeader() {
        let scores = [
            RoundScore(submissionID: 1, points: -1, hiddenGemCount: 0),
            RoundScore(submissionID: 2, points: -4, hiddenGemCount: 0)
        ]

        #expect(scores.leaders.isEmpty)
    }

    @Test
    func anEmptyRoundHasNoLeader() {
        let scores: [RoundScore] = []

        #expect(scores.leaders.isEmpty)
    }
}
