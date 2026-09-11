import Foundation
import Testing
@testable import TodApp

/// The timing behind "a press five seconds after opening a song hung at 0:00".
/// It cannot be reproduced by hand at the speed a tool drives the simulator,
/// so it is pinned here instead.
@Suite
struct EmbedPlayGateTests {
    @Test
    func aPlayBeforeTheTrackIsReadyIsHeldNotSent() {
        var gate = EmbedPlayGate()
        gate.trackLoaded()

        #expect(gate.requestPlay() == false)
        #expect(gate.isPlayQueued)
    }

    /// Released once. A second `ready` for the same track -- or the fallback
    /// arriving after the real signal -- must not start it twice.
    @Test
    func aHeldPlayIsReleasedExactlyOnceWhenReady() {
        var gate = EmbedPlayGate()
        let generation = gate.trackLoaded()
        _ = gate.requestPlay()

        #expect(gate.becameReady() == true)
        #expect(gate.becameReady() == false)
        #expect(gate.becameReady(generation: generation) == false)
        #expect(gate.isPlayQueued == false)
    }

    @Test
    func aPlayAfterReadyGoesOutAtOnce() {
        var gate = EmbedPlayGate()
        gate.trackLoaded()
        _ = gate.becameReady()

        #expect(gate.requestPlay() == true)
    }

    /// Opening another song must not start it because of a press on the last one.
    @Test
    func aNewTrackForgetsThePlayQueuedForTheLastOne() {
        var gate = EmbedPlayGate()
        gate.trackLoaded()
        _ = gate.requestPlay()

        gate.trackLoaded()

        #expect(gate.isPlayQueued == false)
        #expect(gate.becameReady() == false)
    }

    /// A new track also means waiting again: readiness belongs to one track.
    @Test
    func aNewTrackIsNotReadyJustBecauseTheLastOneWas() {
        var gate = EmbedPlayGate()
        gate.trackLoaded()
        _ = gate.becameReady()

        gate.trackLoaded()

        #expect(gate.requestPlay() == false)
    }

    /// The fallback for an earlier track fires late; the current one is still
    /// loading and must not be treated as ready because of it.
    @Test
    func aFallbackForAnEarlierTrackCannotMarkTheCurrentOneReady() {
        var gate = EmbedPlayGate()
        let earlier = gate.trackLoaded()
        gate.trackLoaded()
        _ = gate.requestPlay()

        #expect(gate.becameReady(generation: earlier) == false)
        #expect(gate.isTrackReady == false)
        #expect(gate.isPlayQueued)
    }

    /// If the embed never says it is ready, the fallback for this track is
    /// what keeps the button from being dead.
    @Test
    func theFallbackForTheCurrentTrackReleasesTheHeldPlay() {
        var gate = EmbedPlayGate()
        let current = gate.trackLoaded()
        _ = gate.requestPlay()

        #expect(gate.becameReady(generation: current) == true)
    }

    @Test
    func pausingWhileItIsStillStartingMeansDoNotStart() {
        var gate = EmbedPlayGate()
        gate.trackLoaded()
        _ = gate.requestPlay()

        gate.cancelQueuedPlay()

        #expect(gate.becameReady() == false)
    }
}
