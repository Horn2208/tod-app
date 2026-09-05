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
