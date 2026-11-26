import Foundation

/// When a play request may actually be sent to Spotify's embed.
///
/// The embed takes a command as soon as its frame has loaded, but it can only
/// *play* once its own player has reported `ready` -- and Spotify's controller
/// holds early commands back only while an internal loading flag is set, not
/// until that `ready`. This gate closes that gap: it holds a play for the
/// current track until the embed has said it is ready for exactly that track,
/// then releases it once.
///
/// Measured, the gap is short: `ready` arrived 0.78 s after the load. The gate
/// was written for a real press that hung at 0:00 five seconds after opening a
/// song -- and that press, by this measurement, came well *after* `ready`. So
/// the gate guards a sub-second window and does not explain that failure,
/// whose cause is still open. The trace in `SpotifyEmbedPlayer` is there to
/// catch it next time.
///
/// Pure state with no WebKit in it, so its timing can be tested.
struct EmbedPlayGate: Equatable {
    /// Which load the gate is waiting on. A fallback timer carries the number
    /// it was started for, so a timer left over from an earlier track cannot
    /// mark a later one ready.
    private(set) var generation = 0
    private(set) var isTrackReady = false
    /// A play asked for before the track was ready, held until it is.
    private(set) var isPlayQueued = false

    /// A new track was handed to the embed. Nothing about the previous one
    /// carries over -- least of all a play that was queued for it.
    @discardableResult
    mutating func trackLoaded() -> Int {
        generation += 1
        isTrackReady = false
        isPlayQueued = false
        return generation
    }

    /// Whether the play may go out now. If not, it is held until it may.
    mutating func requestPlay() -> Bool {
        if isTrackReady { return true }
        isPlayQueued = true
        return false
    }

    /// Pausing while a play is still held means "don't start after all".
    mutating func cancelQueuedPlay() {
        isPlayQueued = false
    }

    /// The embed reported ready, or the fallback fired. Returns whether a held
    /// play must be sent now.
    ///
    /// `generation` is nil for the embed's own signal, which concerns the
    /// track it is showing. A fallback passes the generation it was started
    /// for, and is ignored once that is no longer the current one.
    mutating func becameReady(generation fired: Int? = nil) -> Bool {
        if let fired, fired != generation { return false }
        guard !isTrackReady else { return false }
        isTrackReady = true
        let release = isPlayQueued
        isPlayQueued = false
        return release
    }
}
