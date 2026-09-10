import Foundation

/// The shape drawn under a playing track.
///
/// **This is not the song's audio.** Neither Spotify's iFrame API nor the web
/// view hands out samples, so there is nothing real to measure and nothing
/// here pretends otherwise. The shape is derived from the track id: the same
/// song always gets the same one, a different song a different one. It shows
/// *where you are* in a track, which is true, and looks like a waveform while
/// doing it.
enum Waveform {
    /// Heights from 0 to 1, one per bar.
    static func bars(forTrack id: String, count: Int = 44) -> [Double] {
        guard count > 0 else { return [] }
        var state = StableHash.fnv1a(id)
        return (0..<count).map { index in
            // A linear congruential step per bar rather than hashing the id
            // again with the index glued on: neighbouring indices otherwise
            // produce neighbouring hashes and the shape comes out combed.
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let noise = Double((state >> 33) % 1_000) / 1_000

            // A gentle arc over the whole width, so it reads as a song rather
            // than as static: quieter at both ends, fullest in the middle.
            let position = count == 1 ? 0.5 : Double(index) / Double(count - 1)
            let arc = 0.45 + 0.55 * sin(position * .pi)

            // Never zero: a bar of no height is a gap, and a gap reads as a
            // missing bar rather than a quiet moment.
            return min(max(0.14 + 0.86 * noise * arc, 0.14), 1)
        }
    }
}
