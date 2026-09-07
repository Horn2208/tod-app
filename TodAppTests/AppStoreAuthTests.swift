import Foundation
import Testing
@testable import TodApp

@Suite
@MainActor
struct AppStoreAuthTests {
    private var everything: MusicProviderCapabilities {
        MusicProviderCapabilities(
            canSearch: true, canPlayFullTracks: true,
            canStartAtPosition: true, playsInsideTheApp: false
        )
    }

    @Test
    func aFreshStoreIsSignedOut() {
        let store = AppStore(provider: FakeMusicProvider(capabilities: everything))

        #expect(store.isSignedIn == false)
        #expect(store.capabilities == .none)
    }

    /// A launch that will end up signed in must not flash `SignInView` first --
    /// the root view stays neutral for as long as this is true.
    @Test
    func aFreshStoreIsStillRestoringSession() {
        let store = AppStore(provider: FakeMusicProvider(capabilities: everything))

        #expect(store.isRestoringSession)
    }

    /// Covers the "however it finishes" requirement: nothing was stored, so
    /// `restore()` leaves the provider signed out -- restoreSession() must
    /// still settle the flag rather than leaving it stuck on the failure path.
    @Test
    func restoringSessionEndsTheRestoringStateEvenWhenNothingWasStored() async {
        let store = AppStore(provider: FakeMusicProvider(capabilities: everything))

        await store.restoreSession()

        #expect(store.isRestoringSession == false)
        #expect(store.isSignedIn == false)
    }

    @Test
    func signingInPublishesTheProvidersCapabilities() async {
        let store = AppStore(provider: FakeMusicProvider(capabilities: everything))

        await store.signIn()

        #expect(store.isSignedIn)
        #expect(store.capabilities.canStartAtPosition)
    }

    @Test
    func signingOutClearsBoth() async {
        let store = AppStore(provider: FakeMusicProvider(capabilities: everything))
        await store.signIn()

        await store.signOut()

        #expect(store.isSignedIn == false)
        #expect(store.capabilities == .none)
    }

    /// MoreView's sign-out control has nothing that stops it from being
    /// reachable twice in a row (a slow confirmation dialog, a double tap) --
    /// a second `signOut()` on an already-signed-out store must not throw,
    /// crash, or flip anything back on.
    @Test
    func signingOutWhenAlreadySignedOutIsSafe() async {
        let store = AppStore(provider: FakeMusicProvider(capabilities: everything))
        #expect(store.isSignedIn == false)

        await store.signOut()

        #expect(store.isSignedIn == false)
        #expect(store.capabilities == .none)
    }

    /// Declining is a decision, not a failure: no error banner appears.
    @Test
    func aCancelledSignInReportsNoError() async {
        let store = AppStore(
            provider: RefusingProvider(error: .authorizationCancelled)
        )

        await store.signIn()

        #expect(store.isSignedIn == false)
        #expect(store.lastError == nil)
    }

    @Test
    func aFailedSignInIsReported() async {
        let store = AppStore(provider: RefusingProvider(error: .authorizationFailed))

        await store.signIn()

        #expect(store.lastError == .authorizationFailed)
    }

    /// A fresh sign-in used to reach the tab bar with nothing in it: only
    /// `TodApp.swift`'s one-shot `.task` called `loadGroups()`, and it never
    /// re-ran once `isSignedIn` flipped from false to true. The rule now lives
    /// in `AppStore` itself, so every path that ends signed in loads groups.
    @Test
    func signingInLoadsGroupsWhenTheyWereEmpty() async {
        let group = Group(
            id: "test", name: "Test Group", icon: "🧪", members: [], roundEndsAt: .now,
            submissions: [], board: [], chatMessages: [], activeBattle: nil
        )
        let store = AppStore(
            groupRepo: MockGroupRepository(groups: [group]),
            provider: FakeMusicProvider(capabilities: everything)
        )
        #expect(store.groups.isEmpty)

        await store.signIn()

        #expect(store.groups.map(\.id) == ["test"])
    }

    /// Declining sign-in must not reach for groups that require an account.
    @Test
    func aCancelledSignInDoesNotLoadGroups() async {
        let group = Group(
            id: "test", name: "Test Group", icon: "🧪", members: [], roundEndsAt: .now,
            submissions: [], board: [], chatMessages: [], activeBattle: nil
        )
        let store = AppStore(
            groupRepo: MockGroupRepository(groups: [group]),
            provider: RefusingProvider(error: .authorizationCancelled)
        )

        await store.signIn()

        #expect(store.groups.isEmpty)
    }
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
    func play(_ source: TrackSource, from section: TrackSection?) async throws {}
    func stop() async {}
    func playbackUpdates() async -> AsyncStream<TrackSource?> { AsyncStream { _ in } }
}
