import Foundation
import Testing
@testable import TodApp

@Suite
struct PlaybackClockTests {
    private let start = Date(timeIntervalSince1970: 1_000)

    /// The point of it: between two reports the waveform moves on.
    @Test
    func itCountsOnBetweenReports() {
        var clock = PlaybackClock()
        clock.report(position: 10, isPlaying: true, at: start)

        #expect(clock.estimate(at: start.addingTimeInterval(0.5), isPlaying: true, duration: 200) == 10.5)
    }

    @Test
    func pausedItStandsAtTheReport() {
        var clock = PlaybackClock()
        clock.report(position: 10, isPlaying: false, at: start)

        #expect(clock.estimate(at: start.addingTimeInterval(3), isPlaying: false, duration: 200) == 10)
    }

    /// A player that stops reporting has stalled; the waveform stops too.
    @Test
    func itRunsOnlyAShortWayPastTheLastReport() {
        var clock = PlaybackClock()
        clock.report(position: 10, isPlaying: true, at: start)

        #expect(clock.estimate(at: start.addingTimeInterval(30), isPlaying: true, duration: 200)
            == 10 + PlaybackClock.maxLead)
    }

    @Test
    func neverPastTheEnd() {
        var clock = PlaybackClock()
        clock.report(position: 29.8, isPlaying: true, at: start)

        #expect(clock.estimate(at: start.addingTimeInterval(1), isPlaying: true, duration: 30) == 30)
    }

    /// A report a little behind the count is the report arriving late; taking
    /// it would pull the waveform back once a second.
    @Test
    func aSlightlyLateReportDoesNotPullItBack() {
        var clock = PlaybackClock()
        clock.report(position: 10, isPlaying: true, at: start)
        let later = start.addingTimeInterval(1)
        clock.report(position: 10.8, isPlaying: true, at: later)

        #expect(clock.estimate(at: later, isPlaying: true, duration: 200) == 11)
    }

    /// Scrubbing back is a real step back, and it is taken.
    @Test
    func aSeekBackIsTaken() {
        var clock = PlaybackClock()
        clock.report(position: 60, isPlaying: true, at: start)
        let later = start.addingTimeInterval(0.25)
        clock.report(position: 20, isPlaying: true, at: later)

        #expect(clock.estimate(at: later, isPlaying: true, duration: 200) == 20)
    }

    @Test
    func aReportAheadIsTaken() {
        var clock = PlaybackClock()
        clock.report(position: 10, isPlaying: true, at: start)
        let later = start.addingTimeInterval(0.25)
        clock.report(position: 45, isPlaying: true, at: later)

        #expect(clock.estimate(at: later, isPlaying: true, duration: 200) == 45)
    }

    /// Pressing play after a long pause must not jump by the time spent paused.
    @Test
    func playingAgainStartsFromWhereItStood() {
        var clock = PlaybackClock()
        clock.report(position: 10, isPlaying: false, at: start)
        let resumed = start.addingTimeInterval(60)
        clock.report(position: 10, isPlaying: true, at: resumed)

        #expect(clock.estimate(at: resumed, isPlaying: true, duration: 200) == 10)
    }
}
