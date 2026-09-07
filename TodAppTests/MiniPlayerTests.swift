import Foundation
import Testing
@testable import TodApp

@Suite
@MainActor
struct MiniPlayerTests {
    private var everything: MusicProviderCapabilities {
        MusicProviderCapabilities(
            canSearch: true, canPlayFullTracks: true,
            canStartAtPosition: true, playsInsideTheApp: false
        )
    }

    private let source = TrackSource(
        service: .spotify, serviceTrackID: "abc",
        pageURL: URL(string: "https://open.spotify.com/track/abc")!, artworkURL: nil
    )

    /// The bar exists only while something plays, so the store must report
    /// nothing playing on a fresh launch.
    @Test
    func nothingPlaysOnAFreshStore() {
        let store = AppStore(provider: FakeMusicProvider(capabilities: everything))

        #expect(store.currentlyPlaying == nil)
    }

    @Test
    func stoppingClearsWhatIsPlaying() async throws {
        let provider = FakeMusicProvider(capabilities: everything)
        let store = AppStore(provider: provider)
        await store.signIn()
        try await provider.play(source, from: nil)

        await provider.stop()

        // Give the store's stream consumer a turn to observe the change.
        try await Task.sleep(for: .milliseconds(50))
        #expect(store.currentlyPlaying == nil)
    }
}
