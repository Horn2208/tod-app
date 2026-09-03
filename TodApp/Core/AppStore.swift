import Foundation

@MainActor
@Observable
final class AppStore {
    private(set) var groups: [Group] = []
    private(set) var currentGroupID: String = "lnc"
    var lastError: TodAppError?

    /// The current user's own votes for the selected group, and the round's
    /// result once it has been submitted.
    private(set) var myVotes = MyVotes()
    private(set) var roundScores: [RoundScore] = []

    private let groupRepo: GroupRepository
    private let submissionRepo: SubmissionRepository
    private let voteRepo: VoteRepository
    private let leaderboardRepo: LeaderboardRepository
    private let chatRepo: ChatRepository
    private let battleRepo: BattleRepository
    let musicSearch: MusicSearchRepository

    private let currentUserID = "du"

    init(
        groupRepo: GroupRepository = InMemoryRepository.shared,
        submissionRepo: SubmissionRepository = InMemoryRepository.shared,
        voteRepo: VoteRepository = InMemoryRepository.shared,
        leaderboardRepo: LeaderboardRepository = InMemoryRepository.shared,
        chatRepo: ChatRepository = InMemoryRepository.shared,
        battleRepo: BattleRepository = InMemoryRepository.shared,
        musicSearch: MusicSearchRepository = AppStore.defaultMusicSearch()
    ) {
        self.groupRepo = groupRepo
        self.submissionRepo = submissionRepo
        self.voteRepo = voteRepo
        self.leaderboardRepo = leaderboardRepo
        self.chatRepo = chatRepo
        self.battleRepo = battleRepo
        self.musicSearch = musicSearch
    }

    /// Missing credentials must surface in the search field, not as a crash at
    /// launch -- so a failure here becomes a repository that always throws.
    static func defaultMusicSearch() -> MusicSearchRepository {
        do {
            let credentials = try SpotifyCredentials.fromBundle()
            return SpotifySearchRepository(
                tokenProvider: SpotifyTokenProvider(credentials: credentials)
            )
        } catch {
            return FailingMusicSearchRepository(error: .missingSpotifyCredentials)
        }
    }

    var currentGroup: Group? {
        groups.first { $0.id == currentGroupID }
    }

    func selectGroup(_ id: String) {
        currentGroupID = id
    }

    func loadGroups() async {
        await run { self.groups = try await self.groupRepo.fetchGroups() }
    }

    func submit(_ submission: Submission) async {
        guard let groupID = currentGroup?.id else { return }
        await run {
            try await self.submissionRepo.submit(submission, to: groupID)
            self.groups = try await self.groupRepo.fetchGroups()
        }
    }

    func post(candidate: TrackCandidate) async {
        guard let group = currentGroup else { return }
        let submission = Submission(
            id: (group.submissions.map(\.id).max() ?? 0) + 1,
            posterID: currentUserID,
            track: candidate.title,
            artist: candidate.artist,
            coverColorHex: "#b3527a",
            comments: [],
            source: candidate.source
        )
        await submit(submission)
    }

    /// Loads what this user already voted, so the round survives leaving the tab
    /// or closing the app.
    func loadMyVotes() async {
        guard let groupID = currentGroup?.id else { return }
        await run {
            self.myVotes = try await self.voteRepo.fetchMyVotes(voterID: self.currentUserID, groupID: groupID)
            if self.myVotes.hasSubmitted {
                self.roundScores = try await self.voteRepo.fetchRoundScores(groupID: groupID)
            } else {
                self.roundScores = []
            }
        }
    }

    func castVote(_ rating: Rating, for submissionID: Int) async {
        guard let groupID = currentGroup?.id, !myVotes.hasSubmitted else { return }
        let vote = Vote(voterID: currentUserID, submissionID: submissionID, rating: rating, isHiddenGem: false)
        await run(tolerating: .alreadyVoted) {
            try await self.voteRepo.castVote(vote, groupID: groupID)
            self.myVotes.ratings[submissionID] = rating
        }
    }

    func toggleHiddenGem(_ submissionID: Int) async {
        guard let groupID = currentGroup?.id, !myVotes.hasSubmitted else { return }
        await run(tolerating: .alreadyVoted) {
            try await self.voteRepo.setHiddenGem(
                submissionID: submissionID, voterID: self.currentUserID, groupID: groupID)
            self.myVotes.hiddenGemID = self.myVotes.hiddenGemID == submissionID ? nil : submissionID
        }
    }

    func submitVotes() async {
        guard let groupID = currentGroup?.id else { return }
        await run {
            try await self.voteRepo.submitVotes(voterID: self.currentUserID, groupID: groupID)
            self.myVotes.hasSubmitted = true
            self.roundScores = try await self.voteRepo.fetchRoundScores(groupID: groupID)
        }
    }

    func sendMessage(_ text: String) async {
        guard let groupID = currentGroup?.id else { return }
        let message = ChatMessage(id: UUID(), authorTag: "DU", authorName: "Du", text: text, isFromCurrentUser: true)
        await run {
            try await self.chatRepo.sendMessage(message, groupID: groupID)
            self.groups = try await self.groupRepo.fetchGroups()
        }
    }

    /// Some failures are expected states rather than problems -- voting after the
    /// round was submitted is a dead end the UI already shows, not an alert.
    private func run(
        tolerating tolerated: TodAppError,
        _ action: @MainActor @escaping () async throws -> Void
    ) async {
        do {
            try await action()
        } catch let error as TodAppError where error == tolerated {
            return
        } catch let error as TodAppError {
            lastError = error
        } catch {
            lastError = .network(underlying: error)
        }
    }

    private func run(_ action: @MainActor @escaping () async throws -> Void) async {
        do {
            try await action()
        } catch let error as TodAppError {
            lastError = error
        } catch {
            lastError = .network(underlying: error)
        }
    }
}
