import Foundation

/// A colour for a song that has no artwork, or whose artwork has not loaded.
///
/// Every posted song used to get the same pink, which made the glow behind the
/// card on Home identical for every song a person posted -- the one place the
/// brief wanted each song to look like itself. Deriving the hue from the track
/// instead costs nothing, never flickers, and gives the same song the same
/// colour every time, the way the waveform's shape already works.
enum CoverColor {
    static func hex(forTrack id: String) -> String {
        let hue = Double(fnv1a(id) % 360)
        // Fixed saturation and lightness: the hue may roam, but a colour sitting
        // behind white text on a dark ground may not.
        let (r, g, b) = rgb(hue: hue / 360, saturation: 0.42, lightness: 0.26)
        return String(format: "#%02x%02x%02x", Int(r * 255), Int(g * 255), Int(b * 255))
    }

    private static func fnv1a(_ text: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return hash
    }

    private static func rgb(
        hue: Double, saturation: Double, lightness: Double
    ) -> (Double, Double, Double) {
        let c = (1 - abs(2 * lightness - 1)) * saturation
        let x = c * (1 - abs((hue * 6).truncatingRemainder(dividingBy: 2) - 1))
        let m = lightness - c / 2
        let (r, g, b): (Double, Double, Double) = switch hue * 6 {
        case ..<1: (c, x, 0)
        case ..<2: (x, c, 0)
        case ..<3: (0, c, x)
        case ..<4: (0, x, c)
        case ..<5: (x, 0, c)
        default: (c, 0, x)
        }
        return (r + m, g + m, b + m)
    }
}
