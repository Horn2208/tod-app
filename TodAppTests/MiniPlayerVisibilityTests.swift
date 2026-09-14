import Foundation
import Testing
@testable import TodApp

@Suite
struct MiniPlayerVisibilityTests {
    private let pause = Date(timeIntervalSince1970: 1_000)

    @Test
    func whilePlayingItShows() {
        #expect(MiniPlayerVisibility.isVisible(isPlaying: true, pausedAt: nil, now: pause))
    }

    /// Pausing and going on within a moment must not make it jump away and back.
    @Test
    func itStaysAMomentAfterAPause() {
        #expect(MiniPlayerVisibility.isVisible(isPlaying: false, pausedAt: pause, now: pause.addingTimeInterval(2)))
    }

    @Test
    func thenItGoes() {
        #expect(!MiniPlayerVisibility.isVisible(
            isPlaying: false, pausedAt: pause, now: pause.addingTimeInterval(MiniPlayerVisibility.linger)))
    }

    @Test
    func withNothingPlayedItNeverShows() {
        #expect(!MiniPlayerVisibility.isVisible(isPlaying: false, pausedAt: nil, now: pause))
    }

    /// The brief asks for three to five seconds.
    @Test
    func theMomentIsThreeToFiveSeconds() {
        #expect((3.0...5.0).contains(MiniPlayerVisibility.linger))
    }
}
