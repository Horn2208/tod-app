import Foundation

@MainActor
@Observable
final class AppStore {
    private(set) var groups: [Group] = []
    private(set) var currentGroupID: String = "lnc"
    var lastError: TodAppError?

    private(set) var isSignedIn = false
    private(set) var capabilities: MusicProviderCapabilities = .none
    /// True until `restoreSession()` has finished, however it finishes. A
    /// launch that will end up signed in must not flash `SignInView` first --
    /// the root view stays on a neutral placeholder while this is true.
    private(set) var isRestoringSession = true

    /// Mirrors `provider.playbackUpdates()`: the track currently playing, or
    /// `nil` when nothing is. Views read this instead of keeping their own
    /// play/stop flag -- only the provider knows when playback stops on its
    /// own, and this is where that fact actually arrives.
    private(set) var currentlyPlaying: TrackSource?
    /// Holds the task that consumes `provider.playbackUpdates()`, so it can
    /// be cancelled when this store goes away. Deliberately NOT a plain
    /// `@MainActor` stored property: this store's own `deinit` cannot touch
    /// one of those directly, and the task's closure captures `self` only
    /// weakly (below) so this store does not depend on that cancellation to
    /// be deallocated in the first place -- but the task itself, awaiting a
    /// stream that never finishes on its own, would otherwise keep running
    /// forever. `PlaybackObservation` is a plain, non-isolated object for
    /// exactly this reason: its own `deinit` can cancel the task
    /// synchronously the moment this store (the only thing holding it) is
    /// deallocated.
    private let playbackObservation = PlaybackObservation()

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
    let provider: any MusicProvider

    private let currentUserID = "du"

    /// The current user's own name and picture. Kept separate from `Member`
    /// -- which describes how a user shows up inside a group -- because a
    /// profile exists once per person, independent of any group.
    private(set) var profile = UserProfile(id: "du", name: "Du", imageData: nil)

    init(
        groupRepo: GroupRepository = InMemoryRepository.shared,
        submissionRepo: SubmissionRepository = InMemoryRepository.shared,
        voteRepo: VoteRepository = InMemoryRepository.shared,
        leaderboardRepo: LeaderboardRepository = InMemoryRepository.shared,
        chatRepo: ChatRepository = InMemoryRepository.shared,
        battleRepo: BattleRepository = InMemoryRepository.shared,
        provider: any MusicProvider = AppStore.defaultProvider()
    ) {
        self.groupRepo = groupRepo
        self.submissionRepo = submissionRepo
        self.voteRepo = voteRepo
        self.leaderboardRepo = leaderboardRepo
        self.chatRepo = chatRepo
        self.battleRepo = battleRepo
        self.provider = provider
        observePlayback()
    }

    /// Starts the one, long-lived consumption of `provider.playbackUpdates()`
    /// for this store's whole lifetime -- there is exactly one provider and
    /// exactly one owner of it, so there is no sign-in/sign-out moment that
    /// needs a second subscription: the provider keeps publishing through
    /// sign-out same as any other state change.
    private func observePlayback() {
        let provider = provider
        playbackObservation.task = Task { [weak self] in
            for await track in await provider.playbackUpdates() {
                self?.currentlyPlaying = track
            }
        }
    }

    /// Stops playback. A thin forward to the provider -- it already cancels
    /// its own end-of-section timer and publishes the resulting `nil` through
    /// `playbackUpdates()`, which `observePlayback()` mirrors into
    /// `currentlyPlaying`. Nothing here duplicates that.
    func stopPlayback() async {
        await provider.stop()
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

    /// Updates the current user's name and/or picture. `imageData: nil` means
    /// "leave the picture alone", not "remove it" -- the profile screen edits
    /// the two independently, so renaming must not wipe a picture that was
    /// already chosen. A blank (or whitespace-only) name is refused rather
    /// than accepted, so clearing the field and tapping away cannot leave the
    /// user nameless.
    func updateProfile(name: String, imageData: Data?) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { profile.name = trimmed }
        if let imageData { profile.imageData = imageData }
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
            coverColorHex: CoverColor.hex(forTrack: candidate.source.serviceTrackID),
            comments: [],
            source: candidate.source,
            section: section,
            postedAt: Date()
        )
        await submit(submission)
    }

    /// Loads what this user already voted in the round that is running, and the
    /// result of the round that is on show. Both survive leaving the tab or
    /// closing the app.
    func loadMyVotes() async {
        guard let groupID = currentGroup?.id else { return }
        await run {
            self.myVotes = try await self.voteRepo.fetchMyVotes(
                voterID: self.currentUserID, groupID: groupID, day: Date())
            // Only the revealed day is ever fetched. Today's scores are not
            // hidden by a view -- they are never asked for, and a number that
            // never arrives cannot leak onto a screen.
            self.roundScores = try await self.voteRepo.fetchRoundScores(
                groupID: groupID, day: RoundVisibility.revealedDay())
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

    /// Whether this submission's round is still running. A submission the
    /// current group does not have is not votable either -- there is no round
    /// here to belong to.
    private func isVotable(_ submissionID: Int) -> Bool {
        guard let submission = currentGroup?.submissions.first(where: { $0.id == submissionID })
        else { return false }
        return RoundVisibility.isVotable(roundDay: submission.postedAt)
    }

    /// The round being played: today's songs, this user's own included, so the
    /// round keeps its real size on screen.
    var runningSubmissions: [Submission] {
        RoundVisibility.runningSubmissions(from: currentGroup?.submissions ?? [])
    }

    /// The round on show: yesterday's songs, with their scores. Empty in a
    /// group that posted nothing yesterday -- an older round is not pulled
    /// forward to fill the screen.
    var revealedSubmissions: [Submission] {
        RoundVisibility.revealedSubmissions(from: currentGroup?.submissions ?? [])
    }

    /// The submissions this user is asked to judge -- today's round, minus
    /// their own song.
    var votableSubmissions: [Submission] {
        runningSubmissions.filter { !isOwn($0) }
    }

    func castVote(_ rating: Rating, for submissionID: Int) async {
        guard let groupID = currentGroup?.id, isVotable(submissionID) else { return }
        guard !isOwnSubmission(submissionID) else { return }
        let vote = Vote(voterID: currentUserID, submissionID: submissionID, rating: rating, isHiddenGem: false)
        await run(tolerating: .roundClosed) {
            try await self.voteRepo.castVote(vote, groupID: groupID)
            self.myVotes.ratings[submissionID] = rating
        }
    }

    func toggleHiddenGem(_ submissionID: Int) async {
        guard let groupID = currentGroup?.id, isVotable(submissionID) else { return }
        guard !isOwnSubmission(submissionID) else { return }
        await run(tolerating: .roundClosed) {
            try await self.voteRepo.setHiddenGem(
                submissionID: submissionID, voterID: self.currentUserID, groupID: groupID)
            self.myVotes.hiddenGemID = self.myVotes.hiddenGemID == submissionID ? nil : submissionID
        }
    }

    /// The group a submission belongs to. Not `currentGroup`: a song is reached
    /// from the story row too, which spans every group, so "the one selected"
    /// is not a safe answer to "which group is this song in" -- and the comment
    /// would land in the wrong one, or nowhere.
    func group(containing submissionID: Int) -> Group? {
        groups.first { $0.submissions.contains { $0.id == submissionID } }
    }

    /// Says something under a song, as the current user. The repository assigns
    /// the comment's id, where the existing ones are -- the same division of
    /// labour as posting a submission.
    func addComment(_ text: String, to submissionID: Int) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let groupID = group(containing: submissionID)?.id else { return }
        await run {
            try await self.submissionRepo.addComment(
                trimmed,
                authorID: self.profile.id,
                authorName: self.profile.name,
                submissionID: submissionID,
                groupID: groupID
            )
            // A comment lives inside the group's submission, so the groups this
            // store hands to views have to be read back -- the same reload
            // `sendMessage` does for chat.
            self.groups = try await self.groupRepo.fetchGroups()
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
        // `defer` rather than an assignment at the end: this must flip to
        // false on every exit from this function, including one added later
        // that returns early or throws, not just the happy path visible today.
        defer { isRestoringSession = false }
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

/// Holds the `Task` that consumes a provider's `playbackUpdates()`.
/// Deliberately not `@MainActor`: `AppStore`'s own `deinit` cannot touch a
/// `@MainActor`-isolated stored property directly, but this plain object's
/// `deinit` can access its own `task` synchronously the moment `AppStore` --
/// the only thing holding it -- is deallocated, and that is what actually
/// stops the task from awaiting a stream that never finishes on its own.
private final class PlaybackObservation {
    var task: Task<Void, Never>?
    deinit { task?.cancel() }
}
