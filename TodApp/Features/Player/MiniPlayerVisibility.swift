import Foundation

/// When the mini player shows: while something plays, and for a moment after
/// a pause. Without that moment, pausing and going on made it vanish and come
/// straight back.
enum MiniPlayerVisibility {
    /// Seconds it stays after a pause.
    static let linger: TimeInterval = 4

    static func isVisible(isPlaying: Bool, pausedAt: Date?, now: Date) -> Bool {
        if isPlaying { return true }
        guard let pausedAt else { return false }
        return now.timeIntervalSince(pausedAt) < linger
    }
}
