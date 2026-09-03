import Foundation
import Testing
@testable import TodApp

/// Records votes in memory so the store's behaviour can be observed without
/// the shared singleton, which other suites also touch.
actor MockVoteRepository: VoteRepository {
    private var votes: [String: Vote] = [:]
    private var hiddenGem: [String: Int] = [:]
    private var submitted: Set<String> = []
    private(set) var roundScores: [RoundScore] = []

    init(roundScores: [RoundScore] = []) {
        self.roundScores = roundScores
    }

    func castVote(_ vote: Vote, groupID: String) async throws {
        guard !submitted.contains("\(vote.voterID)-\(groupID)") else { throw TodAppError.alreadyVoted }
        votes["\(vote.voterID)-\(vote.submissionID)-\(groupID)"] = vote
    }

    func setHiddenGem(submissionID: Int, voterID: String, groupID: String) async throws {
        guard !submitted.contains("\(voterID)-\(groupID)") else { throw TodAppError.alreadyVoted }
        let key = "\(voterID)-\(groupID)"
        hiddenGem[key] = hiddenGem[key] == submissionID ? nil : submissionID
    }

    func submitVotes(voterID: String, groupID: String) async throws {
        submitted.insert("\(voterID)-\(groupID)")
    }

    func fetchMyVotes(voterID: String, groupID: String) async throws -> MyVotes {
        var ratings: [Int: Rating] = [:]
        for (_, vote) in votes where vote.voterID == voterID {
            ratings[vote.submissionID] = vote.rating
        }
        return MyVotes(
            ratings: ratings,
            hiddenGemID: hiddenGem["\(voterID)-\(groupID)"],
            hasSubmitted: submitted.contains("\(voterID)-\(groupID)")
        )
    }

    func fetchRoundScores(groupID: String) async throws -> [RoundScore] {
        roundScores
    }
}

private func makeGroup() -> Group {
    Group(
        id: "test", name: "Test", icon: "🧪",
        members: [Member(id: "du", name: "Du", isCurrentUser: true, hasPostedToday: true)],
        roundEndsAt: .now,
        submissions: [
            Submission(id: 1, posterID: "mats", track: "A", artist: "X", coverColorHex: "#111111", comments: []),
            Submission(id: 2, posterID: "lena", track: "B", artist: "Y", coverColorHex: "#222222", comments: []),
            Submission(id: 3, posterID: "du", track: "C", artist: "Z", coverColorHex: "#333333", comments: [])
        ],
        board: [], chatMessages: [], activeBattle: nil
    )
}

@Suite
@MainActor
struct VotingFlowTests {
    private func makeStore(_ votes: MockVoteRepository) async -> AppStore {
        let store = AppStore(
            groupRepo: MockGroupRepository(groups: [makeGroup()]),
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

    @Test
    func submittingMarksTheRoundDoneAndLoadsItsScores() async {
        let repo = MockVoteRepository(roundScores: [
            RoundScore(submissionID: 1, points: 3, hiddenGemCount: 1),
            RoundScore(submissionID: 2, points: -1, hiddenGemCount: 0)
        ])
        let store = await makeStore(repo)
        await store.castVote(.good, for: 1)

        await store.submitVotes()

        #expect(store.myVotes.hasSubmitted)
        #expect(store.roundScores.map(\.submissionID) == [1, 2])
        #expect(store.lastError == nil)
    }

    /// Voting again after submitting is an expected dead end, not a failure to
    /// shout about -- the repository throws, and the store must swallow it.
    @Test
    func votingAfterSubmittingDoesNotRaiseAnError() async {
        let store = await makeStore(MockVoteRepository())
        await store.castVote(.ok, for: 1)
        await store.submitVotes()

        await store.castVote(.awful, for: 1)

        #expect(store.lastError == nil)
        #expect(store.myVotes.ratings[1] == .ok)
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

    /// The submit button waits for every song this user is asked to judge, so
    /// counting their own would leave the round impossible to finish.
    @Test
    func theVotableListLeavesOutYourOwnSong() async {
        let store = await makeStore(MockVoteRepository())

        #expect(store.currentGroup?.submissions.count == 3)
        #expect(store.votableSubmissions.map(\.id) == [1, 2])
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
    func scoresSumEveryVoterSRatingPerSubmission() async throws {
        let repo = InMemoryRepository()
        try await repo.castVote(
            Vote(voterID: "du", submissionID: 1, rating: .banger, isHiddenGem: false), groupID: "lnc")
        try await repo.castVote(
            Vote(voterID: "mats", submissionID: 1, rating: .good, isHiddenGem: false), groupID: "lnc")
        try await repo.castVote(
            Vote(voterID: "lena", submissionID: 2, rating: .awful, isHiddenGem: false), groupID: "lnc")

        let scores = try await repo.fetchRoundScores(groupID: "lnc")

        #expect(scores.first { $0.submissionID == 1 }?.points == 3)   // 2 + 1
        #expect(scores.first { $0.submissionID == 2 }?.points == -2)
    }

    @Test
    func aSubmissionNobodyRatedScoresZeroRatherThanVanishing() async throws {
        let repo = InMemoryRepository()
        let group = try await repo.fetchGroup(id: "lnc")

        let scores = try await repo.fetchRoundScores(groupID: "lnc")

        #expect(scores.count == group.submissions.count)
        #expect(scores.allSatisfy { $0.points == 0 })
    }

    @Test
    func hiddenGemsAreCountedButDoNotChangeThePoints() async throws {
        let repo = InMemoryRepository()
        try await repo.castVote(
            Vote(voterID: "du", submissionID: 1, rating: .ok, isHiddenGem: false), groupID: "lnc")
        try await repo.setHiddenGem(submissionID: 1, voterID: "du", groupID: "lnc")

        let scores = try await repo.fetchRoundScores(groupID: "lnc")
        let first = try #require(scores.first { $0.submissionID == 1 })

        #expect(first.hiddenGemCount == 1)
        #expect(first.points == 0)  // .ok is worth nothing on its own
    }

    @Test
    func votingIsRefusedOnceTheRoundHasBeenSubmitted() async throws {
        let repo = InMemoryRepository()
        try await repo.submitVotes(voterID: "du", groupID: "lnc")

        await #expect(throws: TodAppError.alreadyVoted) {
            try await repo.castVote(
                Vote(voterID: "du", submissionID: 1, rating: .good, isHiddenGem: false), groupID: "lnc")
        }
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
