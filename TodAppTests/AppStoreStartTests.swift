import Foundation
import Testing
@testable import TodApp

/// Answers the start screen's two new ways in as the test says.
actor StartAccountService: AccountService {
    private let spotify: Result<AccountUser, Error>
    private let anonymous: Result<AccountUser, Error>

    init(
        spotify: Result<AccountUser, Error> = .failure(TodAppError.accountSignInFailed),
        anonymous: Result<AccountUser, Error> = .failure(TodAppError.accountSignInFailed)
    ) {
        self.spotify = spotify
        self.anonymous = anonymous
    }

    func restore() async -> AccountUser? { nil }
    func signInWithApple(idToken: String, nonce: String, name: String?) async throws -> AccountUser {
        throw TodAppError.accountSignInFailed
    }
    func signInWithSpotify() async throws -> AccountUser { try spotify.get() }
    func signInAnonymously() async throws -> AccountUser { try anonymous.get() }
    func signOut() async {}
}

/// The start screen offers three ways in: Apple, Spotify, or none. Each ends
/// in an account, because the server gives nothing to nobody; they differ in
/// what the account can be found again with.
@Suite
@MainActor
struct AppStoreStartTests {
    private let listener = AccountUser(id: "5b0f1f1e-0000-0000-0000-000000000001")
    private let guest = AccountUser(id: "a7a7a7a7-0000-0000-0000-000000000002", isAnonymous: true)

    private func groups() -> MockGroupRepository {
        MockGroupRepository(groups: [Group(
            id: "g", name: "G", icon: "🎵", members: [], roundEndsAt: .now,
            submissions: [], chatMessages: [], activeBattle: nil)])
    }

    private func store(
        accounts: StartAccountService, provider: any MusicProvider = FakeMusicProvider(capabilities: .none)
    ) -> AppStore {
        AppStore(
            groupRepo: groups(), profileRepo: RecordingProfileRepository(),
            provider: provider, accountService: accounts)
    }

    // MARK: Spotify

    /// One sign-in, and the account is there and Spotify plays.
    @Test
    func signingInWithSpotifyOpensTheAppAndConnectsSpotify() async {
        let store = store(accounts: StartAccountService(spotify: .success(listener)))

        await store.signInWithSpotify()

        #expect(store.account == listener)
        #expect(store.groups.map(\.id) == ["g"])
        #expect(store.isSpotifyConnected)
        #expect(store.lastError == nil)
    }

    /// Closing Spotify's page is a decision, not an error.
    @Test
    func closingSpotifysPageIsNoError() async {
        let store = store(accounts: StartAccountService(spotify: .failure(TodAppError.authorizationCancelled)))

        await store.signInWithSpotify()

        #expect(store.isSignedIn == false)
        #expect(store.lastError == nil)
    }

    @Test
    func aFailedSpotifySignInSaysSo() async {
        let store = store(accounts: StartAccountService(spotify: .failure(URLError(.notConnectedToInternet))))

        await store.signInWithSpotify()

        #expect(store.isSignedIn == false)
        #expect(store.lastError == .accountSignInFailed)
    }

    /// The account came through; the music connection is a second page and
    /// may be closed. The app still opens, Spotify can be connected later.
    @Test
    func decliningTheMusicConnectionStillOpensTheApp() async {
        let store = store(
            accounts: StartAccountService(spotify: .success(listener)),
            provider: RefusingProvider(error: .authorizationCancelled))

        await store.signInWithSpotify()

        #expect(store.account == listener)
        #expect(store.isSpotifyConnected == false)
        #expect(store.lastError == nil)
    }

    // MARK: No sign-in

    @Test
    func continuingWithoutSigningInMakesAnAccountOnThisPhone() async {
        let store = store(accounts: StartAccountService(anonymous: .success(guest)))

        await store.continueWithoutAccount()

        #expect(store.account == guest)
        #expect(store.account?.isAnonymous == true)
        #expect(store.groups.map(\.id) == ["g"])
    }

    @Test
    func aFailedStartWithoutAccountSaysSo() async {
        let store = store(accounts: StartAccountService(anonymous: .failure(URLError(.timedOut))))

        await store.continueWithoutAccount()

        #expect(store.isSignedIn == false)
        #expect(store.lastError == .accountSignInFailed)
    }

    @Test
    func anAccountIsNotAnonymousUnlessSaid() {
        #expect(AccountUser(id: "x").isAnonymous == false)
    }
}
