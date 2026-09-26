import Foundation

/// Where playback is between two reports from the player, so the waveform
/// glides instead of stepping.
///
/// The players report their position now and then: `AVPlayer` four times a
/// second, SoundCloud's widget about once. Drawn as reported, the lit part of
/// the waveform jumps with every report. This counts on from the last report
/// at the speed a song plays -- one second per second -- and is set right
/// again by the next one.
struct PlaybackClock: Equatable {
    /// The position the clock counts on from, and when it was set.
    private(set) var anchor: Double = 0
    private(set) var anchoredAt: Date = .distantPast

    /// A report this far behind the clock is the report's own lateness -- the
    /// widget measured it a moment before it arrived -- and not a step back
    /// in the song. The clock keeps its own count then, or every report
    /// would pull the waveform back a hair.
    static let lateness: Double = 0.5
    /// How far the clock runs past the last report. A player that stalls
    /// (buffering, a dropped connection) stops reporting; the waveform stops
    /// soon after rather than running on through silence.
    static let maxLead: Double = 1.5

    /// Takes what the player reports: its position, and whether it plays.
    mutating func report(position: Double, isPlaying: Bool, at now: Date) {
        if isPlaying {
            let counted = estimate(at: now, isPlaying: true, duration: 0)
            if position <= counted, counted - position < Self.lateness {
                anchor = counted
                anchoredAt = now
                return
            }
        }
        anchor = position
        anchoredAt = now
    }

    /// Seconds into the song at `now`. Paused, that is exactly the last
    /// report. Never past the end, when the length is known (above zero).
    func estimate(at now: Date, isPlaying: Bool, duration: Double) -> Double {
        guard isPlaying else { return anchor }
        let lead = min(max(now.timeIntervalSince(anchoredAt), 0), Self.maxLead)
        let position = anchor + lead
        return duration > 0 ? min(position, duration) : position
    }
}
