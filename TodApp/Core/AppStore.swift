import Foundation

@MainActor
@Observable
final class AppStore {
    private(set) var groups: [Group] = []
    private(set) var currentGroupID: String = "lnc"
    var lastError: TodAppError?

    private(set) var isSignedIn = false
    private(set) var capabilities: MusicProviderCapabilities = .none

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
    // TODO(task 10): PostSongView still gets its search repository from here.
    // Once it reads `provider` instead, this property and `defaultMusicSearch()`
    // below can go.
    let musicSearch: MusicSearchRepository
    let provider: any MusicProvider

    private let currentUserID = "du"

    init(
        groupRepo: GroupRepository = InMemoryRepository.shared,
        submissionRepo: SubmissionRepository = InMemoryRepository.shared,
        voteRepo: VoteRepository = InMemoryRepository.shared,
        leaderboardRepo: LeaderboardRepository = InMemoryRepository.shared,
        chatRepo: ChatRepository = InMemoryRepository.shared,
        battleRepo: BattleRepository = InMemoryRepository.shared,
        musicSearch: MusicSearchRepository = AppStore.defaultMusicSearch(),
        provider: any MusicProvider = AppStore.defaultProvider()
    ) {
        self.groupRepo = groupRepo
        self.submissionRepo = submissionRepo
        self.voteRepo = voteRepo
        self.leaderboardRepo = leaderboardRepo
        self.chatRepo = chatRepo
        self.battleRepo = battleRepo
        self.musicSearch = musicSearch
        self.provider = provider
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

    /// The one provider this version ships with. The client id is public --
    /// PKCE means there is no secret to hide.
    static func defaultProvider() -> any MusicProvider {
        let clientID = Bundle.main.object(forInfoDictionaryKey: "SpotifyClientID") as? String ?? ""
        return SpotifyProvider(
            clientID: clientID,
            tokenStore: KeychainTokenStore(),
            exchange: SpotifyTokenExchange(
                clientID: clientID,
                redirectURI: "todapp://auth/spotify"
            ),
            presentSignIn: WebAuthentication.presentSignIn
        )
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

    func post(candidate: TrackCandidate, section: TrackSection? = nil) async {
        guard currentGroup != nil else { return }
        let submission = Submission(
            // Across every group, not just this one: the seed numbers groups
            // consecutively, so minting from the posting group alone hands out
            // an id the next group already uses.
            id: (groups.flatMap(\.submissions).map(\.id).max() ?? 0) + 1,
            posterID: currentUserID,
            track: candidate.title,
            artist: candidate.artist,
            coverColorHex: "#b3527a",
            comments: [],
            source: candidate.source,
            section: section
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

    /// Nobody votes for their own song -- it would be a free point, and the round
    /// is meant to be judged by everyone else. The view needs this to lock the
    /// card; the guards below make it a rule rather than a UI convention.
    func isOwn(_ submission: Submission) -> Bool {
        submission.posterID == currentUserID
    }

    private func isOwnSubmission(_ submissionID: Int) -> Bool {
        guard let submission = currentGroup?.submissions.first(where: { $0.id == submissionID })
        else { return false }
        return isOwn(submission)
    }

    /// The submissions this user is asked to judge -- everything except their own.
    var votableSubmissions: [Submission] {
        (currentGroup?.submissions ?? []).filter { !isOwn($0) }
    }

    func castVote(_ rating: Rating, for submissionID: Int) async {
        guard let groupID = currentGroup?.id, !myVotes.hasSubmitted else { return }
        guard !isOwnSubmission(submissionID) else { return }
        let vote = Vote(voterID: currentUserID, submissionID: submissionID, rating: rating, isHiddenGem: false)
        await run(tolerating: .alreadyVoted) {
            try await self.voteRepo.castVote(vote, groupID: groupID)
            self.myVotes.ratings[submissionID] = rating
        }
    }

    func toggleHiddenGem(_ submissionID: Int) async {
        guard let groupID = currentGroup?.id, !myVotes.hasSubmitted else { return }
        guard !isOwnSubmission(submissionID) else { return }
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

    func restoreSession() async {
        await provider.restore()
        await refreshSession()
    }

    func signIn() async {
        do {
            try await provider.authorize()
        } catch TodAppError.authorizationCancelled {
            // Declining is a decision, not something to shout about.
        } catch let error as TodAppError {
            lastError = error
        } catch {
            lastError = .network(underlying: error)
        }
        await refreshSession()
    }

    func signOut() async {
        await provider.signOut()
        await refreshSession()
    }

    /// Every path that can end signed in (`signIn()`, `restoreSession()`) funnels
    /// through here, so this is also the one place that decides whether groups
    /// need loading. Putting that rule in a view's `.task` instead once meant a
    /// fresh sign-in reached the tab bar with nothing in it: the `.task` ran once
    /// for the view's lifetime and never re-fired when `isSignedIn` flipped to
    /// true later.
    private func refreshSession() async {
        isSignedIn = await provider.isAuthorized
        capabilities = await provider.capabilities
        if isSignedIn {
            await loadGroups()
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
