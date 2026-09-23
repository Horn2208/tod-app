import Foundation
import Testing
@testable import TodApp

/// The app's own account: signed in with Apple, and the only thing that
/// decides whether the app opens and loads groups.
@Suite
@MainActor
struct AppStoreAccountTests {
    private let lena = AccountUser(id: "0b6f7c1e-lena")

    private func group() -> Group {
        Group(
            id: "test", name: "Test Group", icon: "🧪", members: [], roundEndsAt: .now,
            submissions: [], chatMessages: [], activeBattle: nil
        )
    }

    @Test
    func aFreshStoreIsSignedOutAndStillRestoring() {
        let store = AppStore(provider: FakeMusicProvider(capabilities: .none), accountService: FakeAccountService())

        #expect(store.isSignedIn == false)
        #expect(store.isRestoringSession)
    }

    /// "However it finishes": nothing was stored, and the flag still settles.
    @Test
    func restoringWithNoAccountEndsSignedOut() async {
        let store = AppStore(provider: FakeMusicProvider(capabilities: .none), accountService: FakeAccountService())

        await store.restoreSession()

        #expect(store.isRestoringSession == false)
        #expect(store.isSignedIn == false)
    }

    @Test
    func aRestoredAccountOpensTheAppWithItsGroups() async {
        let store = AppStore(
            groupRepo: MockGroupRepository(groups: [group()]),
            provider: FakeMusicProvider(capabilities: .none),
            accountService: FakeAccountService(restored: lena)
        )

        await store.restoreSession()

        #expect(store.account == lena)
        #expect(store.groups.map(\.id) == ["test"])
    }

    /// A fresh sign-in once reached the tab bar with nothing in it; loading
    /// the groups belongs to signing in.
    @Test
    func signingInWithAppleLoadsTheGroups() async {
        let accounts = FakeAccountService()
        let store = AppStore(
            groupRepo: MockGroupRepository(groups: [group()]),
            provider: FakeMusicProvider(capabilities: .none),
            accountService: accounts
        )

        await store.signInWithApple(idToken: "token", nonce: "nonce", name: "Lena")

        #expect(store.isSignedIn)
        #expect(store.groups.map(\.id) == ["test"])
        #expect(await accounts.lastName == "Lena")
    }

    @Test
    func aFailedAppleSignInIsReportedAndOpensNothing() async {
        let store = AppStore(
            groupRepo: MockGroupRepository(groups: [group()]),
            provider: FakeMusicProvider(capabilities: .none),
            accountService: FakeAccountService(failure: .accountSignInFailed)
        )

        await store.signInWithApple(idToken: "token", nonce: "nonce", name: nil)

        #expect(store.isSignedIn == false)
        #expect(store.lastError == .accountSignInFailed)
        #expect(store.groups.isEmpty)
    }

    /// A phone handed on keeps neither the account nor the music login.
    @Test
    func signingOutLeavesTheAccountAndSpotify() async {
        let accounts = FakeAccountService(restored: lena)
        let store = AppStore(
            groupRepo: MockGroupRepository(groups: [group()]),
            provider: FakeMusicProvider(capabilities: .none),
            accountService: accounts
        )
        await store.restoreSession()
        await store.connectSpotify()

        await store.signOut()

        #expect(store.isSignedIn == false)
        #expect(store.isSpotifyConnected == false)
        #expect(store.groups.isEmpty)
        #expect(await accounts.didSignOut)
    }

    /// Without a backend the app runs on its in-memory data, as its user.
    @Test
    func aBuildWithoutABackendIsItsLocalUser() async {
        let store = AppStore(provider: FakeMusicProvider(capabilities: .none))

        await store.restoreSession()

        #expect(store.account == LocalAccountService.user)
    }
}

/// Spotify: optional, connected in the profile, and never the way into the app.
@Suite
@MainActor
struct AppStoreSpotifyConnectionTests {
    private var everything: MusicProviderCapabilities {
        MusicProviderCapabilities(
            canSearch: true, canPlayFullTracks: true,
            canStartAtPosition: true, playsInsideTheApp: false
        )
    }

    @Test
    func aFreshStoreHasNoSpotify() {
        let store = AppStore(provider: FakeMusicProvider(capabilities: everything))

        #expect(store.isSpotifyConnected == false)
        #expect(store.capabilities == .none)
    }

    @Test
    func connectingPublishesTheProvidersCapabilities() async {
        let store = AppStore(provider: FakeMusicProvider(capabilities: everything))

        await store.connectSpotify()

        #expect(store.isSpotifyConnected)
        #expect(store.capabilities.canStartAtPosition)
    }

    @Test
    func connectingSpotifyDoesNotSignIntoTheApp() async {
        let store = AppStore(provider: FakeMusicProvider(capabilities: everything), accountService: FakeAccountService())

        await store.connectSpotify()

        #expect(store.isSignedIn == false)
    }

    @Test
    func disconnectingClearsBoth() async {
        let store = AppStore(provider: FakeMusicProvider(capabilities: everything))
        await store.connectSpotify()

        await store.disconnectSpotify()

        #expect(store.isSpotifyConnected == false)
        #expect(store.capabilities == .none)
    }

    /// A slow confirmation dialog or a double tap can reach this twice.
    @Test
    func disconnectingWhenNotConnectedIsSafe() async {
        let store = AppStore(provider: FakeMusicProvider(capabilities: everything))

        await store.disconnectSpotify()

        #expect(store.isSpotifyConnected == false)
        #expect(store.capabilities == .none)
    }

    /// Declining is a decision, not a failure: no error banner appears.
    @Test
    func aCancelledConnectionReportsNoError() async {
        let store = AppStore(provider: RefusingProvider(error: .authorizationCancelled))

        await store.connectSpotify()

        #expect(store.isSpotifyConnected == false)
        #expect(store.lastError == nil)
    }

    @Test
    func aFailedConnectionIsReported() async {
        let store = AppStore(provider: RefusingProvider(error: .authorizationFailed))

        await store.connectSpotify()

        #expect(store.lastError == .authorizationFailed)
    }
}

/// Signed out until signed in; says what it was asked.
actor FakeAccountService: AccountService {
    private let restored: AccountUser?
    private let failure: TodAppError?
    private(set) var lastName: String?
    private(set) var didSignOut = false

    init(restored: AccountUser? = nil, failure: TodAppError? = nil) {
        self.restored = restored
        self.failure = failure
    }

    func restore() -> AccountUser? { restored }

    func signInWithApple(idToken: String, nonce: String, name: String?) throws -> AccountUser {
        if let failure { throw failure }
        lastName = name
        return AccountUser(id: "apple-user")
    }

    func signOut() { didSignOut = true }
}

/// A provider whose door is always shut.
actor RefusingProvider: MusicProvider {
    nonisolated let service: MusicService = .spotify
    private let error: TodAppError

    init(error: TodAppError) { self.error = error }

    var isAuthorized: Bool { false }
    var capabilities: MusicProviderCapabilities { .none }
    func authorize() async throws { throw error }
    func restore() async {}
    func signOut() async {}
    func searchTracks(matching query: String) async throws -> [TrackCandidate] { [] }
    func play(_ source: TrackSource, from section: TrackSection?, stopsAtSectionEnd: Bool) async throws {}
    func stop() async {}
    func playbackUpdates() async -> AsyncStream<TrackSource?> { AsyncStream { _ in } }
}
