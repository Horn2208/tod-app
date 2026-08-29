import Foundation

@MainActor
@Observable
final class AppStore {
    private(set) var groups: [Group] = []
    private(set) var currentGroupID: String = "lnc"
    var lastError: TodAppError?

    private let groupRepo: GroupRepository
    private let submissionRepo: SubmissionRepository
    private let voteRepo: VoteRepository
    private let leaderboardRepo: LeaderboardRepository
    private let chatRepo: ChatRepository
    private let battleRepo: BattleRepository

    private let currentUserID = "du"

    init(
        groupRepo: GroupRepository = InMemoryRepository.shared,
        submissionRepo: SubmissionRepository = InMemoryRepository.shared,
        voteRepo: VoteRepository = InMemoryRepository.shared,
        leaderboardRepo: LeaderboardRepository = InMemoryRepository.shared,
        chatRepo: ChatRepository = InMemoryRepository.shared,
        battleRepo: BattleRepository = InMemoryRepository.shared
    ) {
        self.groupRepo = groupRepo
        self.submissionRepo = submissionRepo
        self.voteRepo = voteRepo
        self.leaderboardRepo = leaderboardRepo
        self.chatRepo = chatRepo
        self.battleRepo = battleRepo
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

    func castVote(_ rating: Rating, for submissionID: Int) async {
        guard let groupID = currentGroup?.id else { return }
        let vote = Vote(voterID: currentUserID, submissionID: submissionID, rating: rating, isHiddenGem: false)
        await run { try await self.voteRepo.castVote(vote, groupID: groupID) }
    }

    func toggleHiddenGem(_ submissionID: Int) async {
        guard let groupID = currentGroup?.id else { return }
        await run {
            try await self.voteRepo.setHiddenGem(submissionID: submissionID, voterID: self.currentUserID, groupID: groupID)
        }
    }

    func submitVotes() async {
        guard let groupID = currentGroup?.id else { return }
        await run { try await self.voteRepo.submitVotes(voterID: self.currentUserID, groupID: groupID) }
    }

    func sendMessage(_ text: String) async {
        guard let groupID = currentGroup?.id else { return }
        let message = ChatMessage(id: UUID(), authorTag: "DU", authorName: "Du", text: text, isFromCurrentUser: true)
        await run {
            try await self.chatRepo.sendMessage(message, groupID: groupID)
            self.groups = try await self.groupRepo.fetchGroups()
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
