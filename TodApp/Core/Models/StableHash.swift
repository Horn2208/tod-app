import Foundation

/// One hash, used wherever this app needs the same input to look the same way
/// every time -- a song's fallback colour, a song's waveform shape.
///
/// Its own type rather than a copy in each: two of these drifting apart would
/// mean a track whose colour and shape came from different songs, and this
/// project has already had to catch the same helper duplicated four times.
enum StableHash {
    static func fnv1a(_ text: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return hash
    }
}
