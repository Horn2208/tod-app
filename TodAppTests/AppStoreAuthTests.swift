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
}
