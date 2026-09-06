import Foundation
import Testing
@testable import TodApp

/// `TrackPlayerSheet`'s button used to keep its own `@State isPlaying`,
/// flipped only by its own tap -- so when the provider stopped playback on
/// its own (its end-of-section timer), the button kept lying about what was
/// happening. `AppStore` now mirrors what the provider publishes, and this
/// pins that mirroring on its own, independent of any specific view.
@Suite
@MainActor
struct AppStorePlaybackTests {
    private var everything: MusicProviderCapabilities {
        MusicProviderCapabilities(
            canSearch: true, canPlayFullTracks: true,
            canStartAtPosition: true, playsInsideTheApp: false
        )
    }

    private func source(_ id: String) -> TrackSource {
        TrackSource(
            service: .soundcloud, serviceTrackID: id,
            pageURL: URL(string: "https://soundcloud.com/a/\(id)")!, artworkURL: nil
        )
    }

    @Test
    func appStoreMirrorsWhatTheProviderPublishes() async throws {
        let store = AppStore(provider: FakeMusicProvider(capabilities: everything))
        #expect(store.currentlyPlaying == nil)

        try await store.provider.play(source("a"), from: nil)
        await waitUntil { store.currentlyPlaying == self.source("a") }
        #expect(store.currentlyPlaying == self.source("a"))

        await store.provider.stop()
        await waitUntil { store.currentlyPlaying == nil }
        #expect(store.currentlyPlaying == nil)
    }
}
