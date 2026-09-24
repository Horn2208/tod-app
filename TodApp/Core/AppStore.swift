import Foundation
import os

@MainActor
@Observable
final class AppStore {
    private(set) var groups: [Group] = []
    /// The group chosen last. It may not be among `groups` -- a fresh account
    /// has none of the ones a previous account chose -- and then the first
    /// group stands in (`currentGroup`).
    private var selectedGroupID: String?
    /// False until the groups have been read once, and again after signing
    /// out. An empty `groups` means "no groups" only when this is true; after
    /// a failed load it means nothing yet.
    private(set) var hasLoadedGroups = false
    /// True when the last attempt to read the groups failed.
    private(set) var groupsLoadFailed = false
    var lastError: TodAppError? {
        didSet { if lastError != nil { errorCount &+= 1 } }
    }
    /// How many errors have been raised. The banner watches this rather than
    /// `lastError`: `.network` never equals itself, so a change of that value
    /// cannot be told from no change.
    private(set) var errorCount = 0

    /// The signed-in account; nil when signed out. The app's own identity,
    /// separate from any music service (`AccountService`).
    private(set) var account: AccountUser?
    var isSignedIn: Bool { account != nil }
    /// Whether Spotify is connected. Optional: it brings Spotify search and
    /// Spotify's player, not the way into the app.
    private(set) var isSpotifyConnected = false
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
    /// result once it has been revealed.
    private(set) var myVotes = MyVotes()
    private(set) var roundScores: [RoundScore] = []
    /// Every vote cast in the revealed round -- everyone's, this user's
    /// included. Only ever the revealed one: today's are nobody's business,
    /// so they are never fetched.
    private(set) var revealedVotes: [Vote] = []

    private let groupRepo: GroupRepository
    private let submissionRepo: SubmissionRepository
    private let voteRepo: VoteRepository
    private let chatRepo: ChatRepository
    private let battleRepo: BattleRepository
    private let profileRepo: ProfileRepository
    let provider: any MusicProvider
    private let accountService: any AccountService
    private let reminders: any ReminderScheduling
    /// Only the reminders read the clock through this -- they are the one
    /// thing here whose answer depends on the hour, not just the day.
    private let now: @Sendable () -> Date

    /// Who is using the app: the signed-in account, or the local person of the
    /// in-memory data when nobody is signed in.
    private var currentUserID: String { account?.id ?? LocalAccountService.user.id }

    /// The current user's own name and picture. Kept separate from `Member`
    /// -- which describes how a user shows up inside a group -- because a
    /// profile exists once per person, independent of any group.
    private(set) var profile = AppStore.placeholderProfile(for: LocalAccountService.user.id)

    private static func placeholderProfile(for userID: String, isPremium: Bool = false) -> UserProfile {
        UserProfile(id: userID, name: "Du", imageData: nil, isPremium: isPremium)
    }

    private static let log = Logger(subsystem: "com.lennetschierhorn.TodApp", category: "store")

    init(
        groupRepo: GroupRepository = InMemoryRepository.shared,
        submissionRepo: SubmissionRepository = InMemoryRepository.shared,
        voteRepo: VoteRepository = InMemoryRepository.shared,
        chatRepo: ChatRepository = InMemoryRepository.shared,
        battleRepo: BattleRepository = InMemoryRepository.shared,
        profileRepo: ProfileRepository = InMemoryRepository.shared,
        provider: any MusicProvider = AppStore.defaultProvider(),
        // Local by default, so tests and previews never reach a server; the
        // app builds its store with `AppStore.live()`.
        accountService: any AccountService = LocalAccountService(),
        reminders: any ReminderScheduling = UserNotificationReminders(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.groupRepo = groupRepo
        self.submissionRepo = submissionRepo
        self.voteRepo = voteRepo
        self.chatRepo = chatRepo
        self.battleRepo = battleRepo
        self.profileRepo = profileRepo
        self.provider = provider
        self.accountService = accountService
        self.reminders = reminders
        self.now = now
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

    /// The store the app runs on. With a Supabase project in this build
    /// (`SupabaseConfig`), accounts and data both live there and share one
    /// client -- one session for both. Without one, everything stays in
    /// memory and the local person is signed in.
    static func live() -> AppStore {
        guard let config = SupabaseConfig.bundled else {
            return AppStore(accountService: LocalAccountService())
        }
        let client = config.makeClient()
        let data = SupabaseRepository(client: client)
        return AppStore(
            groupRepo: data, submissionRepo: data, voteRepo: data,
            chatRepo: data, battleRepo: data, profileRepo: data,
            accountService: SupabaseAccountService(client: client))
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

    func submit(_ submission: Submission) async {
        guard let groupID = currentGroup?.id else { return }
        await run {
            try await self.submissionRepo.submit(submission, to: groupID)
            self.groups = try await self.groupRepo.fetchGroups()
        }
        // A post can be what takes today's 15:00 reminder back.
        await syncReminders()
    }

    /// `appleMusicID` is the catalog match, when one was found while the song
    /// was open in the post sheet -- stored so nobody has to search again. A
    /// hit from Apple's own search carries its id already.
    func post(candidate: TrackCandidate, section: TrackSection? = nil, appleMusicID: String? = nil) async {
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
    func castVote(_ rating: Rating, for submissionID: Int, note: String? = nil) async {
        guard let groupID = currentGroup?.id, isVotable(submissionID) else { return }
        guard !isOwnSubmission(submissionID) else { return }
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let kept = (trimmed?.isEmpty ?? true) ? nil : trimmed
        let vote = Vote(
            voterID: currentUserID, submissionID: submissionID, rating: rating,
            isHiddenGem: false, note: kept
        )
        await run(tolerating: .roundClosed) {
            try await self.voteRepo.castVote(vote, groupID: groupID)
            self.myVotes.ratings[submissionID] = rating
            self.myVotes.notes[submissionID] = kept
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
        return currentGroup?.members.first { $0.id == voterID }?.name ?? voterID
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

    /// Turns Tod Premium on or off. Stands in for a purchase until there is
    /// one -- every lock in the app already reads this, so wiring a real
    /// receipt later means changing what writes here, not the screens.
    func setPremium(_ isPremium: Bool) {
        profile.isPremium = isPremium
    }

    /// Sends a simulated reminder broadcast to all group members.
    /// Premium-gated; for the prototype stage this is an in-app banner,
    /// not a real push notification (see spec 3f).
    func sendReminderBroadcast() -> Bool {
        guard profile.isPremium else { return false }
        guard let group = currentGroup else { return false }
        // Simulated: the banner is shown in the view. In a later stage,
        // this would trigger a Supabase Edge Function + APNs push.
        return !group.members.isEmpty
    }

    /// The season table of the selected group, loaded alongside it. Empty
    /// until a round has been revealed.
    private(set) var seasonTotals: [SeasonTotal] = []

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

    /// While the chosen group's chat is open: each time someone writes, read
    /// the groups again, so the message appears without pulling the list
    /// down. Ends when the caller's task does.
    func followChat() async {
        guard let groupID = currentGroup?.id else { return }
        for await _ in chatRepo.newMessages(groupID: groupID) {
            // Quietly: a reload that fails here is no reason to put an error
            // over the chat -- the next message or a pull tries again.
            if let groups = try? await groupRepo.fetchGroups() {
                self.groups = groups
            }
        }
    }

    func sendMessage(_ text: String, mentionedSubmissionID: Int? = nil) async {
        guard let groupID = currentGroup?.id else { return }
        let message = ChatMessage(id: UUID(), authorTag: "DU", authorName: "Du", text: text, isFromCurrentUser: true, mentionedSubmissionID: mentionedSubmissionID)
        await run {
            try await self.chatRepo.sendMessage(message, groupID: groupID)
            self.groups = try await self.groupRepo.fetchGroups()
        }
    }

    // MARK: - Reminders

    /// Whether the system lets this app remind. The profile reads it, because
    /// that is where reminders are switched on.
    private(set) var reminderAuthorization: ReminderAuthorization = .notDetermined
    /// The last plan handed over, so the next one waits for it. Two plans
    /// running at once can interleave: one clears what the other just added.
    private var reminderSync: Task<Void, Never>?

    func refreshReminderAuthorization() async {
        reminderAuthorization = await reminders.authorization()
    }

    /// Asks the system -- the prompt only ever appears the first time -- and
    /// plans straight away, so the first reminder does not wait for the next
    /// load.
    func enableReminders() async {
        reminderAuthorization = await reminders.requestAuthorization()
        await syncReminders()
    }

    /// Plans the reminders again from the groups as they are now. Called
    /// wherever the answer can change: groups loaded, a song posted, the app
    /// back in front on what may be a new day.
    func syncReminders() async {
        let today = now()
        let statuses = groups.compactMap { group -> DailyReminders.GroupStatus? in
            guard let me = group.members.first(where: { $0.id == currentUserID }) else { return nil }
            return DailyReminders.GroupStatus(
                name: group.name,
                hasPostedToday: Member.hasPosted(on: today, in: me.postedDates))
        }
        let plan = DailyReminders.plan(for: statuses, now: today)
        let previous = reminderSync
        let reminders = reminders
        let sync = Task {
            await previous?.value
            await reminders.replaceAll(with: plan)
        }
        reminderSync = sync
        await sync.value
    }

    func restoreSession() async {
        // `defer` rather than an assignment at the end: this must flip to
        // false on every exit from this function, including one added later
        // that returns early or throws, not just the happy path visible today.
        defer { isRestoringSession = false }
        let restored = await accountService.restore()
        await provider.restore()
        await refreshSpotify()
        if let restored {
            await begin(restored)
        }
    }

    /// Everything that follows from someone being signed in: who they are,
    /// and what is theirs.
    private func begin(_ user: AccountUser) async {
        account = user
        if profile.id != user.id {
            profile = Self.placeholderProfile(for: user.id, isPremium: profile.isPremium)
        }
        await loadProfile()
        await loadGroups()
    }

    /// Signs in with what Sign in with Apple handed over, and loads the groups
    /// straight away. Loading lives here, not in a view's `.task`: that once
    /// ran for the view's lifetime only, and a fresh sign-in reached the tab
    /// bar with nothing in it.
    func signInWithApple(idToken: String, nonce: String, name: String?) async {
        do {
            let user = try await accountService.signInWithApple(
                idToken: idToken, nonce: nonce, name: name)
            await begin(user)
        } catch let error as TodAppError {
            lastError = error
        } catch {
            lastError = .accountSignInFailed
        }
    }

    /// Signs in with Spotify, then connects Spotify for playing. The second
    /// page runs on the Spotify session the first one made, so it asks for
    /// consent at most, never for the password again. Closing it leaves the
    /// account signed in; Spotify can be connected in the profile later.
    func signInWithSpotify() async {
        do {
            let user = try await accountService.signInWithSpotify()
            await begin(user)
        } catch TodAppError.authorizationCancelled {
            // Closing Spotify's page is a decision, not an error.
            return
        } catch {
            lastError = .accountSignInFailed
            return
        }
        await connectSpotify()
    }

    /// "Ohne Anmeldung": an account that lives on this phone only.
    func continueWithoutAccount() async {
        do {
            let user = try await accountService.signInAnonymously()
            await begin(user)
        } catch {
            lastError = .accountSignInFailed
        }
    }

    /// Leaves the app on this phone: the account, and Spotify with it -- a
    /// phone handed on must not keep someone else's music login.
    func signOut() async {
        await accountService.signOut()
        account = nil
        groups = []
        hasLoadedGroups = false
        groupsLoadFailed = false
        selectedGroupID = nil
        profile = Self.placeholderProfile(for: LocalAccountService.user.id)
        myVotes = MyVotes()
        roundScores = []
        revealedVotes = []
        seasonTotals = []
        await disconnectSpotify()
    }

    func connectSpotify() async {
        do {
            try await provider.authorize()
        } catch TodAppError.authorizationCancelled {
            // Declining is a decision, not something to shout about.
        } catch let error as TodAppError {
            lastError = error
        } catch {
            lastError = .network(underlying: error)
        }
        await refreshSpotify()
    }

    func disconnectSpotify() async {
        await provider.signOut()
        await refreshSpotify()
    }

    private func refreshSpotify() async {
        isSpotifyConnected = await provider.isAuthorized
        capabilities = await provider.capabilities
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
        } catch is CancellationError {
            // The screen that asked has moved on; nobody is waiting.
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
        } catch is CancellationError {
            return
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
