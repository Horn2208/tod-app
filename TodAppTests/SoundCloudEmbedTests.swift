import Foundation
import Testing
@testable import TodApp

/// SoundCloud played hidden, steered by the app's own controls -- the same
/// way Spotify's embed is.
@Suite
struct SoundCloudEmbedTests {
    private let source = TrackLinkParser.parse("https://soundcloud.com/forss/flickermood")!

    /// The widget the hidden player loads: the track, not starting by itself,
    /// and nothing shown that nobody sees.
    @Test
    func theHiddenWidgetDoesNotStartOnItsOwn() throws {
        let url = EmbedURLBuilder.hiddenSoundCloudURL(for: source)
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(url.host == "w.soundcloud.com")
        #expect(items.first { $0.name == "url" }?.value == "https://soundcloud.com/forss/flickermood")
        #expect(items.first { $0.name == "auto_play" }?.value == "false")
    }

    /// What the widget reports, as the player's state: milliseconds become
    /// seconds, pause and play flip the flag, the end pauses.
    @Test
    func reportsBecomeState() {
        var state = SoundCloudPlayback()
        state.apply(["type": "progress", "position": 70_000.0, "duration": 213_886.0])
        #expect(state.position == 70)
        #expect(abs(state.duration - 213.886) < 0.001)

        state.apply(["type": "play"])
        #expect(!state.isPaused)
        state.apply(["type": "pause"])
        #expect(state.isPaused)
        state.apply(["type": "play"])
        state.apply(["type": "finish"])
        #expect(state.isPaused)
        #expect(state.position == state.duration)
    }

    /// The first time playback is under way, a picked start is where it goes
    /// -- the widget itself always begins at zero. Only once.
    @Test
    func thePickedStartIsSoughtOnceWhenPlayBegins() {
        var state = SoundCloudPlayback()
        state.pendingStart = 70
        #expect(state.apply(["type": "play"]) == .seek(to: 70))
        #expect(state.apply(["type": "pause"]) == nil)
        #expect(state.apply(["type": "play"]) == nil)
    }

    @Test
    func aStartPastTheEndIsNotSought() {
        var state = SoundCloudPlayback()
        state.apply(["type": "ready", "duration": 60_000.0])
        state.pendingStart = 90
        #expect(state.apply(["type": "play"]) == nil)
    }

    @Test
    func anErrorIsKept() {
        var state = SoundCloudPlayback()
        state.apply(["type": "error"])
        #expect(state.failed)
    }
}
