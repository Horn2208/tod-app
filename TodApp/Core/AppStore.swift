import Foundation
import os

/// The app's state and everything that changes it. Split by area into
/// `AppStore+Account`, `+Chat`, `+Membership` and `+Reminders`; the state
/// itself is all here, because extensions cannot hold any.
///
/// Its setters are internal rather than `private(set)` since that split:
/// the extensions in the other files write it. Screens only read; every
/// change goes through a method.
@MainActor
@Observable
final class AppStore {
    var groups: [Group] = []
    /// The group chosen last. It may not be among `groups` -- a fresh account
    /// has none of the ones a previous account chose -- and then the first
    /// group stands in (`currentGroup`).
    var selectedGroupID: String?
    /// False until the groups have been read once, and again after signing
    /// out. An empty `groups` means "no groups" only when this is true; after
    /// a failed load it means nothing yet.
    var hasLoadedGroups = false
    /// True when the last attempt to read the groups failed.
    var groupsLoadFailed = false
    var lastError: TodAppError? {
        didSet { if lastError != nil { errorCount &+= 1 } }
    }
    /// How many errors have been raised. The banner watches this rather than
    /// `lastError`: `.network` never equals itself, so a change of that value
    /// cannot be told from no change.
    private(set) var errorCount = 0

    /// The signed-in account; nil when signed out. The app's own identity,
    /// separate from any music service (`AccountService`).
    var account: AccountUser?
    var isSignedIn: Bool { account != nil }
    /// Whether Spotify is connected. Optional: it brings Spotify search and
    /// Spotify's player, not the way into the app.
    var isSpotifyConnected = false
    var capabilities: MusicProviderCapabilities = .none
    /// True until `restoreSession()` has finished, however it finishes. A
    /// launch that will end up signed in must not flash `SignInView` first --
    /// the root view stays on a neutral placeholder while this is true.
    var isRestoringSession = true

    /// The current user's own votes for the selected group, and the round's
    /// result once it has been revealed.
    var myVotes = MyVotes()
    var roundScores: [RoundScore] = []
    /// Every vote cast in the revealed round -- everyone's, this user's
    /// included. Only ever the revealed one: today's are nobody's business,
    /// so they are never fetched.
    var revealedVotes: [Vote] = []

    // MARK: - State the extensions work on
    //
    // Stored here because extensions cannot hold stored properties; the
    // code that uses each lives in `AppStore+<Area>.swift`.

    /// Whom this user has blocked. Their posts, comments and messages are
    /// already left out of `groups`.
    var blockedIDs: Set<String> = []
    /// Announcements waiting to be read, and the read that will take them.
    var pendingActivity: [GroupActivity] = []
    var pendingRead: Task<Void, Never>?
    /// Whether the system lets this app remind. The profile reads it, because
    /// that is where reminders are switched on.
    var reminderAuthorization: ReminderAuthorization = .notDetermined
    /// The last plan handed over, so the next one waits for it. Two plans
    /// running at once can interleave: one clears what the other just added.
    var reminderSync: Task<Void, Never>?
    /// An invite link that arrived before there was an account to join with.
    var pendingInviteCode: String?
    /// The group a link just brought this user into, for a welcome.
    var joinedByLink: String?
    /// Set on signing out or deleting, cleared by the next sign-in.
    var hasLeft = false
    /// Songs noted for later in the post sheet's search, newest first. On
    /// this phone only, per account (`SavedSongStorage`).
    var savedSongs: [SavedSong] = []

    let groupRepo: GroupRepository
    let submissionRepo: SubmissionRepository
    private let voteRepo: VoteRepository
    let chatRepo: ChatRepository
    private let battleRepo: BattleRepository
    private let profileRepo: ProfileRepository
    let moderationRepo: ModerationRepository
    let provider: any MusicProvider
    let accountService: any AccountService
    let reminders: any ReminderScheduling
    /// Where noted songs are kept (`savedSongs`).
    let savedSongStorage: any SavedSongStorage
    /// The reminders read the clock through this -- they are the one thing
    /// here whose answer depends on the hour, not just the day -- and a noted
    /// song takes its time from it.
    let now: @Sendable () -> Date

    /// Who is using the app: the signed-in account, or the local person of the
    /// in-memory data when nobody is signed in.
    var currentUserID: String { account?.id ?? LocalAccountService.user.id }

    /// The current user's own name and picture. Kept separate from `Member`
    /// -- which describes how a user shows up inside a group -- because a
    /// profile exists once per person, independent of any group.
    var profile = AppStore.placeholderProfile(for: LocalAccountService.user.id)

    static func placeholderProfile(for userID: String, isPremium: Bool = false) -> UserProfile {
        UserProfile(id: userID, name: "Du", imageData: nil, isPremium: isPremium)
    }

    static let log = Logger(subsystem: "com.lennetschierhorn.TodApp", category: "store")

    init(
        groupRepo: GroupRepository = InMemoryRepository.shared,
        submissionRepo: SubmissionRepository = InMemoryRepository.shared,
        voteRepo: VoteRepository = InMemoryRepository.shared,
        chatRepo: ChatRepository = InMemoryRepository.shared,
        battleRepo: BattleRepository = InMemoryRepository.shared,
        profileRepo: ProfileRepository = InMemoryRepository.shared,
        moderationRepo: ModerationRepository = InMemoryRepository.shared,
        provider: any MusicProvider = AppStore.defaultProvider(),
        // Local by default, so tests and previews never reach a server; the
        // app builds its store with `AppStore.live()`.
        accountService: any AccountService = LocalAccountService(),
        reminders: any ReminderScheduling = UserNotificationReminders(),
        // In memory by default, like the repositories: tests never write to
        // the phone. The app passes the file (`live()`).
        savedSongStorage: any SavedSongStorage = InMemorySavedSongStorage(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.groupRepo = groupRepo
        self.submissionRepo = submissionRepo
        self.voteRepo = voteRepo
        self.chatRepo = chatRepo
        self.battleRepo = battleRepo
        self.profileRepo = profileRepo
        self.moderationRepo = moderationRepo
        self.provider = provider
        self.accountService = accountService
        self.reminders = reminders
        self.savedSongStorage = savedSongStorage
        self.now = now
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

    /// The store the app runs on. With a Supabase project in this build
    /// (`SupabaseConfig`), accounts and data both live there and share one
    /// client -- one session for both. Without one, everything stays in
    /// memory and the local person is signed in.
    static func live() -> AppStore {
        let savedSongs = FileSavedSongStorage.applicationSupport()
        guard let config = SupabaseConfig.bundled else {
            return AppStore(accountService: LocalAccountService(), savedSongStorage: savedSongs)
        }
        let client = config.makeClient()
        let data = SupabaseRepository(client: client)
        return AppStore(
            groupRepo: data, submissionRepo: data, voteRepo: data,
            chatRepo: data, battleRepo: data, profileRepo: data, moderationRepo: data,
            accountService: SupabaseAccountService(client: client),
            savedSongStorage: savedSongs)
    }

    var currentGroup: Group? {
        groups.first { $0.id == selectedGroupID } ?? groups.first
    }

    /// The id of `currentGroup`, empty when there is none.
    var currentGroupID: String {
        currentGroup?.id ?? ""
    }

    func selectGroup(_ id: String) {
        selectedGroupID = id
    }

    /// Updates the current user's name and/or picture. `imageData: nil` means
    /// "leave the picture alone", not "remove it" -- the profile screen edits
    /// the two independently, so renaming must not wipe a picture that was
    /// already chosen. A blank (or whitespace-only) name is refused rather
    /// than accepted, so clearing the field and tapping away cannot leave the
    /// user nameless. Shown at once, then saved.
    func updateProfile(name: String, imageData: Data?) async {
        // Just signed out, or the account just deleted: the profile sheet
        // saves as it closes, and there is nobody left to save for.
        guard !hasLeft else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let newName = trimmed.isEmpty || trimmed == profile.name ? nil : trimmed
        guard newName != nil || imageData != nil else { return }
        let before = profile
        if let newName { profile.name = newName }
        if let imageData { profile.imageData = imageData }
        let userID = currentUserID
        // One save after another, and not tied to the screen that asked: an
        // older name must not land after a newer one, and closing the profile
        // must not cancel a save that is already shown as done.
        let previous = profileSave
        let save = Task { () -> Bool in
            _ = await previous?.value
            var saved = false
            await self.run {
                try await self.profileRepo.updateProfile(userID: userID, name: newName, imageData: imageData)
                saved = true
            }
            return saved
        }
        profileSave = save
        guard await save.value == false else { return }
        // Refused: take back what this save put on screen, unless something
        // newer has replaced it since. The error is in `lastError`.
        if let newName, profile.name == newName { profile.name = before.name }
        if let imageData, profile.imageData == imageData { profile.imageData = before.imageData }
    }

    private var profileSave: Task<Bool, Never>?

    /// The signed-in person's profile from the repository. A failure keeps the
    /// placeholder and stays quiet: the groups, loaded next, say whether the
    /// server is there at all.
    func loadProfile() async {
        guard let account else { return }
        do {
            var loaded = try await profileRepo.fetchProfile(userID: account.id)
            // Premium is a local switch until StoreKit writes the server's flag.
            loaded.isPremium = loaded.isPremium || profile.isPremium
            guard self.account == account else { return }
            profile = loaded
        } catch {
            Self.log.error("profile not loaded: \(error.localizedDescription, privacy: .public)")
        }
    }

    func loadGroups() async {
        let errorsBefore = errorCount
        var loaded = false
        await run {
            self.groups = try await self.groupRepo.fetchGroups()
            self.hasLoadedGroups = true
            loaded = true
        }
        // Quietly: who is blocked only labels the member list; the groups
        // above already come without their posts.
        if loaded, let blocked = try? await moderationRepo.fetchBlockedIDs() {
            blockedIDs = blocked
        }
        // A cancelled load raised no error and says nothing either way.
        if loaded {
            groupsLoadFailed = false
        } else if errorCount != errorsBefore {
            groupsLoadFailed = true
        }
        await syncReminders()
    }

    /// What may have changed on other phones: the groups, and this user's
    /// votes in the chosen one. For coming back to the app and for pulling a
    /// list down.
    /// The next turn of a round: midnight in Berlin, where the database
    /// counts (`RoundDay`). The open app reloads then (`RootTabView`).
    static func nextRoundTurn(after now: Date) -> Date {
        let calendar = RoundDay.berlinCalendar
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: 1, to: today) ?? now.addingTimeInterval(86_400)
    }

    func refresh() async {
        // While the session is being restored, that restore loads everything.
        guard isSignedIn, !isRestoringSession else { return }
        await loadGroups()
        await loadMyVotes()
    }

    /// Starts a group and chooses it. False when the name is not one the
    /// database takes, or the server said no (`lastError` says why).
    func createGroup(name: String, icon: String) async -> Bool {
        guard let name = NewGroupDraft.name(name) else { return false }
        let icon = NewGroupDraft.icon(icon)
        var made = false
        await run {
            let id = try await self.groupRepo.createGroup(name: name, icon: icon, asking: self.currentUserID)
            self.groups = try await self.groupRepo.fetchGroups()
            self.hasLoadedGroups = true
            self.selectedGroupID = id
            made = true
        }
        if made { await syncReminders() }
        return made
    }

    /// Joins the group a code belongs to and chooses it. A code that cannot be
    /// one is refused here, without asking the server.
    func joinGroup(code: String) async -> Bool {
        guard InviteCode.isPlausible(code) else {
            lastError = .inviteInvalid
            return false
        }
        var joined = false
        await run {
            let id = try await self.groupRepo.joinGroup(
                code: InviteCode.normalized(code), asking: self.currentUserID)
            self.groups = try await self.groupRepo.fetchGroups()
            self.hasLoadedGroups = true
            self.selectedGroupID = id
            joined = true
        }
        if joined { await syncReminders() }
        return joined
    }

    /// Posts into `groupID`, or the chosen group. A post into another group
    /// than the one on screen makes that group the chosen one, so Home and
    /// the feed that follows show where the song went.
    func submit(_ submission: Submission, to groupID: String? = nil) async {
        guard let groupID = groupID ?? currentGroup?.id else { return }
        await run {
            try await self.submissionRepo.submit(submission, to: groupID)
            self.groups = try await self.groupRepo.fetchGroups()
            if self.selectedGroupID != groupID, self.groups.contains(where: { $0.id == groupID }) {
                self.selectedGroupID = groupID
            }
        }
        // A post can be what takes today's 15:00 reminder back.
        await syncReminders()
    }

    /// `appleMusicID` is the catalog match, when one was found while the song
    /// was open in the post sheet -- stored so nobody has to search again. A
    /// hit from Apple's own search carries its id already.
    func post(
        candidate: TrackCandidate, section: TrackSection? = nil, appleMusicID: String? = nil,
        to groupID: String? = nil
    ) async {
        guard currentGroup != nil else { return }
        let submission = Submission(
            // Across every group, not just this one: the seed numbers groups
            // consecutively, so minting from the posting group alone hands out
            // an id the next group already uses.
            id: (groups.flatMap(\.submissions).map(\.id).max() ?? 0) + 1,
            posterID: currentUserID,
            track: candidate.title,
            artist: candidate.artist,
            // Keyed as `GroupAssembly` keys it, so the colour survives the
            // round trip through the server.
            coverColorHex: CoverColor.hex(
                forTrack: candidate.source?.serviceTrackID ?? "\(candidate.title)|\(candidate.artist)"),
            comments: [],
            source: candidate.source,
            section: section,
            isrc: candidate.isrc,
            appleMusicID: appleMusicID ?? candidate.appleMusicID,
            artworkURL: candidate.source == nil ? candidate.artworkURL : nil,
            durationSeconds: candidate.durationSeconds,
            postedAt: Date()
        )
        await submit(submission, to: groupID)
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
            self.revealedVotes = try await self.voteRepo.fetchVotes(
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
    private func isInCurrentGroup(_ submissionID: Int) -> Bool {
        currentGroup?.submissions.contains { $0.id == submissionID } ?? false
    }

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

    /// Rates a song, with an optional reason. Rating and note travel together
    /// because they are one vote: writing the note on its own would need a
    /// rating to attach to, and there is none until this call has been made.
    /// Set when a rating came too late: the round turned over at midnight
    /// while the feed was open. The feed says so and offers the reveal,
    /// instead of a choice that silently stays empty (the brief's second
    /// audit, A3).
    private(set) var roundIsOver = false

    func acknowledgeRoundOver() {
        roundIsOver = false
    }

    func castVote(_ rating: Rating, for submissionID: Int, note: String? = nil) async {
        guard let groupID = currentGroup?.id else { return }
        guard !isOwnSubmission(submissionID) else { return }
        guard isVotable(submissionID) else {
            // A song of this group whose day is over: midnight passed.
            if isInCurrentGroup(submissionID) { roundIsOver = true }
            return
        }
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let kept = (trimmed?.isEmpty ?? true) ? nil : trimmed
        let vote = Vote(
            voterID: currentUserID, submissionID: submissionID, rating: rating,
            isHiddenGem: false, note: kept
        )
        // Shown at once, written behind: waiting for the server left the
        // field empty for a moment and invited a second tap (the brief's
        // second audit, B2). A refusal puts the old choice back.
        let before = (myVotes.ratings[submissionID], myVotes.notes[submissionID])
        myVotes.ratings[submissionID] = rating
        myVotes.notes[submissionID] = kept
        await run {
            do {
                try await self.voteRepo.castVote(vote, groupID: groupID)
            } catch {
                self.myVotes.ratings[submissionID] = before.0
                self.myVotes.notes[submissionID] = before.1
                if case TodAppError.roundClosed = error {
                    self.roundIsOver = true
                    return
                }
                throw error
            }
        }
    }

    /// Everyone's ratings of one revealed song, newest reader's own included.
    func revealedVotes(for submissionID: Int) -> [Vote] {
        revealedVotes.filter { $0.submissionID == submissionID }
    }

    /// A voter's name inside the selected group, for the reveal. Falls back to
    /// the raw id: someone who has left is still on the round they voted in.
    func voterName(_ voterID: String) -> String {
        if voterID == currentUserID { return "Du" }
        // Someone who has left: never their account id on screen.
        return currentGroup?.members.first { $0.id == voterID }?.name ?? GroupAssembly.formerMemberName
    }

    func toggleHiddenGem(_ submissionID: Int) async {
        guard let groupID = currentGroup?.id else { return }
        guard !isOwnSubmission(submissionID) else { return }
        guard isVotable(submissionID) else {
            // A song of this group whose day is over: midnight passed.
            if isInCurrentGroup(submissionID) { roundIsOver = true }
            return
        }
        // At once, like a rating; a refusal puts the old gem back.
        let before = myVotes.hiddenGemID
        myVotes.hiddenGemID = before == submissionID ? nil : submissionID
        await run {
            do {
                try await self.voteRepo.setHiddenGem(
                    submissionID: submissionID, voterID: self.currentUserID, groupID: groupID)
            } catch {
                self.myVotes.hiddenGemID = before
                if case TodAppError.roundClosed = error {
                    self.roundIsOver = true
                    return
                }
                throw error
            }
        }
    }

    /// Turns Tod Premium on or off. Stands in for a purchase until there is
    /// one -- every lock in the app already reads this, so wiring a real
    /// receipt later means changing what writes here, not the screens.
    func setPremium(_ isPremium: Bool) {
        profile.isPremium = isPremium
    }

    /// The season table of the selected group, loaded alongside it. Empty
    /// until a round has been revealed.
    var seasonTotals: [SeasonTotal] = []

    /// Edits the selected group. Nil leaves a part alone, and so does a blank
    /// name; a name longer than the database takes is cut to fit.
    ///
    /// Each save carries only what it changes, and is compared with the group
    /// as the save before it left it -- not as it was when this one was asked
    /// for. Otherwise a rename typed right after a change of who may invite
    /// would carry the old setting back, and typing a name and then the old
    /// one again would skip the second as "unchanged".
    func updateGroup(name: String? = nil, imageData: Data? = nil, invitePolicy: InvitePolicy? = nil) async {
        guard let groupID = currentGroup?.id else { return }
        let userID = currentUserID
        let previous = groupSave
        let save = Task {
            await previous?.value
            guard let group = self.groups.first(where: { $0.id == groupID }) else { return }
            let rename = name
                .map { BackendRecords.clipped(
                    $0.trimmingCharacters(in: .whitespacesAndNewlines), to: NewGroupDraft.maximumNameLength) }
                .flatMap { $0.isEmpty || $0 == group.name ? nil : $0 }
            // The lever only its creator may move. Guarded here as well as in
            // the view, so a policy cannot be changed by whoever reaches this.
            let policy = invitePolicy.flatMap {
                $0 != group.invitePolicy && GroupPermissions.mayChangeInvitePolicy(userID, of: group) ? $0 : nil
            }
            guard rename != nil || imageData != nil || policy != nil else { return }
            await self.run {
                try await self.groupRepo.updateGroup(
                    id: groupID, name: rename, imageData: imageData, invitePolicy: policy)
                self.groups = try await self.groupRepo.fetchGroups()
            }
        }
        groupSave = save
        await save.value
    }

    private var groupSave: Task<Void, Never>?

    /// A code for someone to join the selected group with. Nil when none
    /// could be made; why is in `lastError`.
    func createInvite() async -> GroupInvite? {
        guard let groupID = currentGroup?.id else { return nil }
        var invite: GroupInvite?
        await run {
            invite = try await self.groupRepo.createInvite(groupID: groupID, asking: self.currentUserID)
        }
        return invite
    }

    /// Whether this user may bring someone into the selected group.
    var mayInvite: Bool {
        guard let group = currentGroup else { return false }
        return GroupPermissions.mayInvite(currentUserID, to: group)
    }

    /// Whether this user may move the invite setting itself.
    var mayChangeInvitePolicy: Bool {
        guard let group = currentGroup else { return false }
        return GroupPermissions.mayChangeInvitePolicy(currentUserID, of: group)
    }

    func loadSeasonTotals() async {
        guard let group = currentGroup else { return }
        await run {
            let scores = try await self.voteRepo.fetchRevealedScores(groupID: group.id)
            self.seasonTotals = SeasonScore.totals(
                members: group.members, submissions: group.submissions, scores: scores)
        }
    }

    func run(_ action: @MainActor @escaping () async throws -> Void) async {
        do {
            try await action()
        } catch is CancellationError {
            return
        } catch let error as TodAppError {
            remember(action, after: error)
            lastError = error
        } catch {
            let error = TodAppError.network(underlying: error)
            remember(action, after: error)
            lastError = error
        }
    }

    // MARK: - Trying again

    /// The last action that failed on the connection, for the banner's
    /// "Nochmal". Only those: a refusal (not allowed, round over) would only
    /// be refused again.
    private var retryable: (@MainActor () async throws -> Void)?

    var canRetry: Bool { retryable != nil }

    private func remember(_ action: @MainActor @escaping () async throws -> Void, after error: TodAppError) {
        if case .network = error {
            retryable = action
        } else {
            retryable = nil
        }
    }

    /// Runs the failed action once more; failing again offers it again.
    func retryLast() async {
        guard let action = retryable else { return }
        retryable = nil
        await run(action)
    }
}
