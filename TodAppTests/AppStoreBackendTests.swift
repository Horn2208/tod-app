import Foundation
import Testing
@testable import TodApp

/// Keeps profiles by id and says what it was asked to change.
actor RecordingProfileRepository: ProfileRepository {
    private var profiles: [String: UserProfile]
    private(set) var updates: [(userID: String, name: String?, imageData: Data?)] = []

    init(_ profiles: [UserProfile] = []) {
        self.profiles = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
    }

    func fetchProfile(userID: String) async throws -> UserProfile {
        guard let profile = profiles[userID] else { throw TodAppError.notFound }
        return profile
    }

    func updateProfile(userID: String, name: String?, imageData: Data?) async throws {
        updates.append((userID, name, imageData))
        if let name { profiles[userID]?.name = name }
        if let imageData { profiles[userID]?.imageData = imageData }
    }
}

/// A group repository whose every read fails the same way.
actor FailingGroupRepository: GroupRepository {
    private let error: Error
    init(_ error: Error) { self.error = error }

    func fetchGroups() async throws -> [Group] { throw error }
    func fetchGroup(id: String) async throws -> Group { throw error }
    func updateGroup(id: String, name: String?, imageData: Data?, invitePolicy: InvitePolicy?) async throws {
        throw error
    }
    func createGroup(name: String, icon: String, asking userID: String) async throws -> String { throw error }
    func createInvite(groupID: String, asking userID: String) async throws -> GroupInvite { throw error }
    func joinGroup(code: String, asking userID: String) async throws -> String { throw error }
}

/// Renames a group only after `slowName` has waited, and notes each rename
/// once it is done -- so a store that lets saves overtake each other shows
/// up as names in the wrong order.
actor SlowRenameRepository: GroupRepository {
    private var group: Group
    private let slowName: String
    private(set) var finished: [String] = []

    init(group: Group, slowName: String) {
        self.group = group
        self.slowName = slowName
    }

    func fetchGroups() async throws -> [Group] { [group] }
    func fetchGroup(id: String) async throws -> Group { group }
    func updateGroup(id: String, name: String?, imageData: Data?, invitePolicy: InvitePolicy?) async throws {
        guard let name else { return }
        if name == slowName { try await Task.sleep(for: .milliseconds(150)) }
        group.name = name
        finished.append(name)
    }
    func createGroup(name: String, icon: String, asking userID: String) async throws -> String { group.id }
    func createInvite(groupID: String, asking userID: String) async throws -> GroupInvite {
        throw TodAppError.notAllowed
    }
    func joinGroup(code: String, asking userID: String) async throws -> String { group.id }
}

/// Notes what each group save asked for, so a test can see which fields a
/// save carried -- and which it left alone.
actor RecordingGroupRepository: GroupRepository {
    struct Save: Equatable {
        let name: String?
        let hasPicture: Bool
        let invitePolicy: InvitePolicy?
    }

    private var group: Group
    private let slowPolicy: Bool
    private(set) var saves: [Save] = []

    init(group: Group, slowPolicy: Bool = false) {
        self.group = group
        self.slowPolicy = slowPolicy
    }

    func fetchGroups() async throws -> [Group] { [group] }
    func fetchGroup(id: String) async throws -> Group { group }
    func updateGroup(id: String, name: String?, imageData: Data?, invitePolicy: InvitePolicy?) async throws {
        if slowPolicy, invitePolicy != nil { try await Task.sleep(for: .milliseconds(150)) }
        if let name { group.name = name }
        if let invitePolicy { group.invitePolicy = invitePolicy }
        saves.append(Save(name: name, hasPicture: imageData != nil, invitePolicy: invitePolicy))
    }
    func createGroup(name: String, icon: String, asking userID: String) async throws -> String { group.id }
    func createInvite(groupID: String, asking userID: String) async throws -> GroupInvite {
        throw TodAppError.notAllowed
    }
    func joinGroup(code: String, asking userID: String) async throws -> String { group.id }
}

/// A profile repository that refuses every save.
actor RefusingProfileRepository: ProfileRepository {
    func fetchProfile(userID: String) async throws -> UserProfile {
        UserProfile(id: userID, name: "Lena", imageData: nil)
    }
    func updateProfile(userID: String, name: String?, imageData: Data?) async throws {
        throw URLError(.notConnectedToInternet)
    }
}

/// Signs in without a password, as a debug build does in the simulator.
actor AnonymousAccountService: AccountService {
    private let user: AccountUser?
    init(user: AccountUser?) { self.user = user }

    func restore() async -> AccountUser? { nil }
    func signInWithApple(idToken: String, nonce: String, name: String?) async throws -> AccountUser {
        throw TodAppError.accountSignInFailed
    }
    func signOut() async {}
    func signInAnonymously() async throws -> AccountUser {
        guard let user else { throw TodAppError.accountSignInFailed }
        return user
    }
}

/// Fails the first read, then answers with no groups.
actor FlakyGroupRepository: GroupRepository {
    private var failed = false

    func fetchGroups() async throws -> [Group] {
        guard failed else {
            failed = true
            throw URLError(.notConnectedToInternet)
        }
        return []
    }
    func fetchGroup(id: String) async throws -> Group { throw TodAppError.notFound }
    func updateGroup(id: String, name: String?, imageData: Data?, invitePolicy: InvitePolicy?) async throws {}
    func createGroup(name: String, icon: String, asking userID: String) async throws -> String { "" }
    func createInvite(groupID: String, asking userID: String) async throws -> GroupInvite {
        throw TodAppError.notAllowed
    }
    func joinGroup(code: String, asking userID: String) async throws -> String { "" }
}

/// Saves a profile, the first name slowly.
actor SlowProfileRepository: ProfileRepository {
    private let slowName: String
    private(set) var finished: [String] = []

    init(slowName: String) { self.slowName = slowName }

    func fetchProfile(userID: String) async throws -> UserProfile {
        UserProfile(id: userID, name: "Du", imageData: nil)
    }
    func updateProfile(userID: String, name: String?, imageData: Data?) async throws {
        if name == slowName { try await Task.sleep(for: .milliseconds(150)) }
        if let name { finished.append(name) }
    }
}

/// The store once knew exactly one person, "du". With an account the user is
/// whoever signed in, and everything the store writes or checks follows that.
@Suite
@MainActor
struct AppStoreBackendTests {
    private let lena = AccountUser(id: "0b6f7c1e-0000-0000-0000-00000000lena")

    private func group(
        _ id: String, name: String, posts: [Submission] = [], creator: String = "du"
    ) -> Group {
        Group(
            id: id, name: name, icon: "🎵",
            members: [Member(id: lena.id, name: "Lena", isCurrentUser: true, postedDates: [])],
            roundEndsAt: .now, submissions: posts, chatMessages: [], activeBattle: nil,
            creatorID: creator)
    }

    private func todaysSong(_ id: Int, by poster: String) -> Submission {
        Submission(id: id, posterID: poster, track: "Song", artist: "A", coverColorHex: "#000000",
                   comments: [], postedAt: Date())
    }

    private func lenasStore(
        groups: any GroupRepository = MockGroupRepository(groups: []),
        votes: any VoteRepository = MockVoteRepository(),
        profiles: any ProfileRepository = RecordingProfileRepository()
    ) -> AppStore {
        AppStore(
            groupRepo: groups, voteRepo: votes, profileRepo: profiles,
            provider: FakeMusicProvider(capabilities: .none),
            accountService: FakeAccountService(restored: lena))
    }

    // MARK: Who the user is

    @Test
    func theRestoredAccountIsTheProfile() async {
        let store = lenasStore(profiles: RecordingProfileRepository([
            UserProfile(id: lena.id, name: "Lena K", imageData: nil),
        ]))

        await store.restoreSession()

        #expect(store.profile.id == lena.id)
        #expect(store.profile.name == "Lena K")
    }

    /// A profile that cannot be read is no reason to shout at someone who has
    /// just opened the app; the groups will say if the server is gone.
    @Test
    func anUnreadableProfileLeavesAPlaceholderAndNoError() async {
        let store = lenasStore()

        await store.restoreSession()

        #expect(store.profile.id == lena.id)
        #expect(!store.profile.name.isEmpty)
        #expect(store.lastError == nil)
    }

    @Test
    func aVoteIsCastAsTheSignedInUser() async throws {
        let votes = MockVoteRepository()
        let store = lenasStore(
            groups: MockGroupRepository(groups: [group("g", name: "G", posts: [todaysSong(1, by: "mats")])]),
            votes: votes)
        await store.restoreSession()

        await store.castVote(.banger, for: 1)

        let mine = try await votes.fetchMyVotes(voterID: lena.id, groupID: "g", day: Date())
        #expect(mine.ratings[1] == .banger)
    }

    @Test
    func theSignedInUsersSongIsTheirOwn() async {
        let store = lenasStore(
            groups: MockGroupRepository(groups: [group("g", name: "G", posts: [todaysSong(1, by: lena.id)])]))
        await store.restoreSession()

        #expect(store.isOwn(todaysSong(1, by: lena.id)))
        #expect(store.votableSubmissions.isEmpty)
    }

    @Test
    func aRenameIsSavedForTheSignedInUser() async {
        let profiles = RecordingProfileRepository([UserProfile(id: lena.id, name: "Lena", imageData: nil)])
        let store = lenasStore(profiles: profiles)
        await store.restoreSession()

        await store.updateProfile(name: "Lena K", imageData: nil)

        let updates = await profiles.updates
        #expect(updates.map(\.userID) == [lena.id])
        #expect(updates.map(\.name) == ["Lena K"])
        #expect(store.profile.name == "Lena K")
    }

    /// The premium switch is a stand-in until StoreKit; loading the profile
    /// from the server must not switch it back off.
    @Test
    func thePremiumSwitchSurvivesLoadingTheProfile() async {
        let store = lenasStore(profiles: RecordingProfileRepository([
            UserProfile(id: lena.id, name: "Lena", imageData: nil, isPremium: false),
        ]))
        store.setPremium(true)

        await store.restoreSession()

        #expect(store.profile.isPremium)
    }

    // MARK: Which group

    /// No group used to be chosen by an id from the demo data; a real account
    /// has none of those.
    @Test
    func withoutAMatchingChoiceTheFirstGroupIsCurrent() async {
        let store = lenasStore(groups: MockGroupRepository(groups: [
            group("a", name: "Alpha"), group("b", name: "Beta"),
        ]))
        await store.restoreSession()

        #expect(store.currentGroup?.id == "a")
        #expect(store.currentGroupID == "a")

        store.selectGroup("gone")
        #expect(store.currentGroup?.id == "a")

        store.selectGroup("b")
        #expect(store.currentGroup?.id == "b")
    }

    @Test
    func groupsCountAsLoadedOnlyOnceTheyHaveBeen() async {
        let store = lenasStore(groups: MockGroupRepository(groups: []))
        #expect(store.hasLoadedGroups == false)

        await store.restoreSession()

        #expect(store.hasLoadedGroups)
        #expect(store.groups.isEmpty)
    }

    /// An empty list after a failed load is not "you have no groups".
    @Test
    func aFailedLoadIsNotAnEmptyList() async {
        let store = lenasStore(groups: FailingGroupRepository(URLError(.notConnectedToInternet)))

        await store.restoreSession()

        #expect(store.hasLoadedGroups == false)
        #expect(store.groupsLoadFailed)
        #expect(store.lastError != nil)
    }

    /// Trying again and succeeding clears the failure.
    @Test
    func aLoadThatWorksClearsAnEarlierFailure() async {
        let store = lenasStore(groups: FlakyGroupRepository())
        await store.restoreSession()
        #expect(store.groupsLoadFailed)

        await store.refresh()

        #expect(store.groupsLoadFailed == false)
        #expect(store.hasLoadedGroups)
    }

    /// The banner counts errors rather than comparing them: two network
    /// errors in a row are two things to say, and `.network` never equals
    /// itself.
    @Test
    func everyNewErrorIsCounted() {
        let store = lenasStore()
        let before = store.errorCount

        store.lastError = .network(underlying: URLError(.timedOut))
        store.lastError = .network(underlying: URLError(.timedOut))
        store.lastError = nil

        #expect(store.errorCount == before + 2)
    }

    // MARK: Saving in order

    /// Typing "Band" then "Bande" must end as "Bande", however long the first
    /// save takes.
    @Test
    func groupRenamesLandInTheOrderTheyWereMade() async {
        let repo = SlowRenameRepository(group: group("g", name: "Alt"), slowName: "Band")
        let store = lenasStore(groups: repo)
        await store.restoreSession()

        let first = Task { await store.updateGroup(name: "Band", imageData: nil, invitePolicy: .everyone) }
        let second = Task { await store.updateGroup(name: "Bande", imageData: nil, invitePolicy: .everyone) }
        await first.value
        await second.value

        #expect(await repo.finished == ["Band", "Bande"])
        #expect(store.currentGroup?.name == "Bande")
    }

    /// Opening the settings writes the name back unchanged; that is no
    /// reason to ask the server anything.
    @Test
    func anUnchangedGroupIsNotSaved() async {
        let repo = SlowRenameRepository(group: group("g", name: "Alt"), slowName: "")
        let store = lenasStore(groups: repo)
        await store.restoreSession()

        await store.updateGroup(name: " Alt ", imageData: nil, invitePolicy: .everyone)
        await store.updateGroup(name: "", imageData: nil, invitePolicy: .everyone)

        #expect(await repo.finished.isEmpty)
    }

    /// Changing who may invite and then typing a name must not bring the old
    /// setting back: a save carries only what it changes.
    @Test
    func aSaveCarriesOnlyWhatItChanges() async {
        let repo = RecordingGroupRepository(group: group("g", name: "Alt", creator: lena.id), slowPolicy: true)
        let store = lenasStore(groups: repo)
        await store.restoreSession()

        let policy = Task { await store.updateGroup(invitePolicy: .creatorOnly) }
        let rename = Task { await store.updateGroup(name: "Neu") }
        await policy.value
        await rename.value

        #expect(await repo.saves == [
            .init(name: nil, hasPicture: false, invitePolicy: .creatorOnly),
            .init(name: "Neu", hasPicture: false, invitePolicy: nil),
        ])
        #expect(store.currentGroup?.invitePolicy == .creatorOnly)
        #expect(store.currentGroup?.name == "Neu")
    }

    /// Typing a name and then the old one again, faster than the first save
    /// takes: the old name has to land last, not be skipped as "unchanged".
    @Test
    func renamingBackWhileTheFirstSaveRunsLandsBack() async {
        let repo = SlowRenameRepository(group: group("g", name: "Alt"), slowName: "A")
        let store = lenasStore(groups: repo)
        await store.restoreSession()

        let first = Task { await store.updateGroup(name: "A") }
        let back = Task { await store.updateGroup(name: "Alt") }
        await first.value
        await back.value

        #expect(await repo.finished == ["A", "Alt"])
        #expect(store.currentGroup?.name == "Alt")
    }

    /// The database takes 40 characters; a longer name is cut, not dropped
    /// without a word.
    @Test
    func anOverlongGroupNameIsCut() async throws {
        let repo = RecordingGroupRepository(group: group("g", name: "Alt"))
        let store = lenasStore(groups: repo)
        await store.restoreSession()

        await store.updateGroup(name: String(repeating: "x", count: 45))

        let saved = try #require(await repo.saves.first?.name)
        #expect(saved.unicodeScalars.count == 40)
    }

    /// A rename the server refused is not left standing as if it had worked.
    @Test
    func aRefusedProfileRenameIsTakenBack() async {
        let store = lenasStore(profiles: RefusingProfileRepository())
        await store.restoreSession()
        #expect(store.profile.name == "Lena")

        await store.updateProfile(name: "Lena K", imageData: nil)

        #expect(store.profile.name == "Lena")
        #expect(store.lastError != nil)
    }

    @Test
    func profileRenamesLandInTheOrderTheyWereMade() async {
        let repo = SlowProfileRepository(slowName: "Len")
        let store = lenasStore(profiles: repo)
        await store.restoreSession()

        let first = Task { await store.updateProfile(name: "Len", imageData: nil) }
        let second = Task { await store.updateProfile(name: "Lena", imageData: nil) }
        await first.value
        await second.value

        #expect(await repo.finished == ["Len", "Lena"])
        #expect(store.profile.name == "Lena")
    }

    /// A request dropped because the screen moved on is nobody's error.
    @Test
    func aCancelledLoadRaisesNoError() async {
        let store = lenasStore(groups: FailingGroupRepository(CancellationError()))

        await store.restoreSession()

        #expect(store.lastError == nil)
    }

    // MARK: Starting and joining

    @Test
    func aNewGroupIsCreatedAndChosen() async {
        let repo = InMemoryRepository()
        let store = AppStore(groupRepo: repo, profileRepo: repo)
        await store.restoreSession()

        let made = await store.createGroup(name: "  Band ", icon: "🎸")

        #expect(made)
        #expect(store.currentGroup?.name == "Band")
        #expect(store.currentGroup?.icon == "🎸")
        #expect(store.currentGroup?.creatorID == "du")
    }

    @Test
    func aBlankNameMakesNoGroup() async {
        let repo = InMemoryRepository()
        let store = AppStore(groupRepo: repo, profileRepo: repo)
        await store.restoreSession()
        let before = store.groups.count

        let made = await store.createGroup(name: "   ", icon: "🎸")

        #expect(made == false)
        #expect(store.groups.count == before)
    }

    @Test
    func joiningWithACodeChoosesThatGroup() async throws {
        let repo = InMemoryRepository()
        let store = AppStore(groupRepo: repo, profileRepo: repo)
        await store.restoreSession()
        store.selectGroup("lnc")
        let invite = try await repo.createInvite(groupID: "wg", asking: "du")

        let joined = await store.joinGroup(code: InviteCode.display(invite.code))

        #expect(joined)
        #expect(store.currentGroup?.id == "wg")
        #expect(store.lastError == nil)
    }

    @Test
    func aMistypedCodeIsRefusedBeforeAskingTheServer() async {
        let store = lenasStore(groups: FailingGroupRepository(URLError(.notConnectedToInternet)))

        let joined = await store.joinGroup(code: "abc")

        #expect(joined == false)
        #expect(store.lastError == .inviteInvalid)
    }

    @Test
    func anUnknownCodeIsRefused() async {
        let repo = InMemoryRepository()
        let store = AppStore(groupRepo: repo, profileRepo: repo)
        await store.restoreSession()

        let joined = await store.joinGroup(code: "0000-0000-0000-0000")

        #expect(joined == false)
        #expect(store.lastError == .inviteInvalid)
    }

    @Test
    func aCodeIsMadeForTheChosenGroupOnlyIfAllowed() async {
        let repo = InMemoryRepository()
        let store = AppStore(groupRepo: repo, profileRepo: repo)
        await store.restoreSession()

        store.selectGroup("wg")
        let open = await store.createInvite()
        store.selectGroup("lnc")
        let closed = await store.createInvite()

        #expect(open?.groupID == "wg")
        #expect(closed == nil)
        #expect(store.lastError == .notAllowed)
    }

    // MARK: Testing without an Apple Account

    /// The simulator has no Apple Account; a debug build signs in without
    /// one, and from there on it is an account like any other.
    @Test
    func anAnonymousSignInIsAnAccountLikeAnyOther() async {
        let tester = AccountUser(id: "7e57e57e-0000-0000-0000-000000000001")
        let store = AppStore(
            groupRepo: MockGroupRepository(groups: [group("g", name: "G")]),
            profileRepo: RecordingProfileRepository([UserProfile(id: tester.id, name: "Neu", imageData: nil)]),
            provider: FakeMusicProvider(capabilities: .none),
            accountService: AnonymousAccountService(user: tester))
        await store.restoreSession()
        #expect(store.isSignedIn == false)

        await store.continueWithoutAccount()

        #expect(store.account == tester)
        #expect(store.profile.name == "Neu")
        #expect(store.groups.map(\.id) == ["g"])
    }

    @Test
    func aFailedAnonymousSignInSaysSo() async {
        let store = AppStore(
            provider: FakeMusicProvider(capabilities: .none),
            accountService: AnonymousAccountService(user: nil))

        await store.continueWithoutAccount()

        #expect(store.isSignedIn == false)
        #expect(store.lastError == .accountSignInFailed)
    }

    // MARK: Coming back and leaving

    /// Someone else posted or joined on another phone; coming back shows it.
    @Test
    func refreshingPicksUpWhatChangedElsewhere() async throws {
        let repo = InMemoryRepository()
        let store = AppStore(groupRepo: repo, profileRepo: repo)
        await store.restoreSession()
        let before = store.groups.count
        _ = try await repo.createGroup(name: "Anderswo", icon: "🎵", asking: "du")

        await store.refresh()

        #expect(store.groups.count == before + 1)
    }

    @Test
    func refreshingWhileSignedOutLoadsNothing() async {
        let store = AppStore(
            groupRepo: MockGroupRepository(groups: [group("g", name: "G")]),
            provider: FakeMusicProvider(capabilities: .none),
            accountService: FakeAccountService())
        await store.restoreSession()

        await store.refresh()

        #expect(store.groups.isEmpty)
    }

    /// The next person on this phone starts from nothing of the last one's.
    @Test
    func signingOutForgetsEverythingOfThisAccount() async {
        let store = lenasStore(
            groups: MockGroupRepository(groups: [
                group("a", name: "A"), group("b", name: "B", posts: [todaysSong(1, by: "mats")]),
            ]),
            profiles: RecordingProfileRepository([UserProfile(id: lena.id, name: "Lena", imageData: Data([1]))]))
        await store.restoreSession()
        store.selectGroup("b")
        await store.castVote(.good, for: 1)
        await store.loadSeasonTotals()
        #expect(store.myVotes.ratings[1] == .good)
        #expect(store.profile.imageData != nil)
        #expect(!store.seasonTotals.isEmpty)

        await store.signOut()

        #expect(store.groups.isEmpty)
        #expect(store.hasLoadedGroups == false)
        #expect(store.profile.id != lena.id)
        #expect(store.profile.imageData == nil)
        #expect(store.myVotes == MyVotes())
        #expect(store.roundScores.isEmpty)
        #expect(store.revealedVotes.isEmpty)
        #expect(store.seasonTotals.isEmpty)
        #expect(store.currentGroup == nil)
    }
}
