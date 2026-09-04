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

/// The bars behind the picker. Spotify publishes no amplitudes, so this is
/// decoration and does not pretend otherwise -- but it is derived from the
/// track id, so one song keeps one shape instead of rerolling on every draw.
enum WaveformShape {
    static func bars(count: Int, seed: String) -> [Double] {
        guard count > 0 else { return [] }
        // Swift's own hashing is seeded per process, so the same track would
        // look different on every launch. FNV-1a is spelled out to stay stable.
        var state = fnv1a(seed)
        return (0..<count).map { index in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let noise = Double((state >> 33) % 1000) / 1000
            let swell = sin(Double(index) * 0.7) * 0.22
            return min(max(0.14 + swell + noise * 0.6, 0.14), 1)
        }
    }

    private static func fnv1a(_ text: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return hash
    }
}
