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

/// What a tap on the mini player opens.
@Suite
struct MiniPlayerTargetTests {
    @Test
    func aLoadedPostOpensWithItsComments() {
        #expect(MiniPlayerTarget.target(submissionID: 7, isLoaded: true, hasItem: true) == .song(7))
    }

    /// Heard while posting: no post yet, but the player still opens.
    @Test
    func withoutAPostThePlayerOpensAlone() {
        #expect(MiniPlayerTarget.target(submissionID: nil, isLoaded: false, hasItem: true) == .item)
    }

    /// A post no longer loaded falls back to the song as it started.
    @Test
    func aPostNotLoadedFallsBackToTheSong() {
        #expect(MiniPlayerTarget.target(submissionID: 7, isLoaded: false, hasItem: true) == .item)
    }

    @Test
    func nothingKnownOpensNothing() {
        #expect(MiniPlayerTarget.target(submissionID: nil, isLoaded: false, hasItem: false) == .none)
    }
}
