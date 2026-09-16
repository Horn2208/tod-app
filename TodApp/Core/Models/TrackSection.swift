import Foundation

/// The stretch of a track a poster picked out. Seconds, not samples: this is a
/// choice about a song, not an edit of audio.
struct TrackSection: Codable, Equatable, Sendable {
    var start: Double
    var end: Double

    /// Short enough to be a hook, long enough to recognise.
    static let minimumDuration: Double = 5
    static let defaultDuration: Double = 30
    /// What a track is assumed to last when nobody told us -- SoundCloud's
    /// oEmbed carries no duration. The picker says so rather than presenting
    /// the resulting timestamps as fact.
    static let assumedDuration: Double = 210

    var duration: Double { end - start }

    /// Opens a third of the way in: a track's first seconds are usually its
    /// least interesting, and the middle is a fair place to start hunting.
    static func initial(in total: Double) -> TrackSection {
        guard total > minimumDuration else { return TrackSection(start: 0, end: max(total, 0)) }
        let length = min(defaultDuration, total)
        let start = min(total / 3, total - length)
        return TrackSection(start: max(start, 0), end: max(start, 0) + length)
    }

    mutating func moveStart(to seconds: Double, in total: Double) {
        start = clamp(seconds, lower: 0, upper: min(end - Self.minimumDuration, total))
    }

    mutating func moveEnd(to seconds: Double, in total: Double) {
        end = clamp(seconds, lower: max(start + Self.minimumDuration, 0), upper: total)
    }

    /// Slides the whole window without stretching it, so running into an edge
    /// parks it there rather than shortening the pick.
    mutating func move(toStart seconds: Double, in total: Double) {
        let length = duration
        let newStart = clamp(seconds, lower: 0, upper: max(total - length, 0))
        start = newStart
        end = newStart + length
    }

    private func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        guard upper > lower else { return lower }
        return min(max(value, lower), upper)
    }
}

/// The song's length as a line, for the picker: where a moment sits along it,
/// and which bars playback has passed.
enum SectionTimeline {
    /// 0 at the song's start, 1 at its end.
    static func fraction(of seconds: Double, in total: Double) -> Double {
        guard total > 0 else { return 0 }
        return min(max(seconds / total, 0), 1)
    }

    /// A bar counts as played once the playhead has reached its middle, so the
    /// fill never runs ahead of the line that marks the playhead.
    static func isPlayed(bar index: Int, of count: Int, playhead: Double, total: Double) -> Bool {
        guard count > 0 else { return false }
        let middle = (Double(index) + 0.5) / Double(count)
        return middle <= fraction(of: playhead, in: total)
    }
}
