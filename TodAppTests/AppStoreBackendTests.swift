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
    func updateGroup(id: String, name: String, imageData: Data?, invitePolicy: InvitePolicy) async throws {
        throw error
    }
    func createGroup(name: String, icon: String, asking userID: String) async throws -> String { throw error }
    func createInvite(groupID: String, asking userID: String) async throws -> GroupInvite { throw error }
    func joinGroup(code: String, asking userID: String) async throws -> String { throw error }
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
        #expect(store.lastError != nil)
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
