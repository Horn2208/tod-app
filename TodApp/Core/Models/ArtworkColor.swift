import Foundation

/// The colour a cover is known by, for the glow behind a song.
///
/// Read from a thumbnail's pixels: grey, near-black and near-white pixels say
/// nothing about a cover and are skipped; the rest are grouped by hue, and the
/// group with the most colour in it wins -- its pixel count weighted by how
/// colourful each pixel is. A vivid subject on a large muted ground therefore
/// beats the ground, which is what the eye picks out too.
///
/// `glow(for:)` then keeps only the hue and sets saturation and lightness to
/// what may sit behind white text on a dark ground, like `CoverColor` does for
/// songs without a cover.
enum ArtworkColor {
    struct RGB: Equatable, Sendable {
        var red: Double
        var green: Double
        var blue: Double
    }

    /// The winning colour, or nil for a cover with no colour to speak of.
    static func dominant(in pixels: [RGB]) -> RGB? {
        var groups: [Int: (score: Double, sum: RGB, count: Double)] = [:]
        for pixel in pixels {
            let hsl = hsl(pixel)
            guard hsl.chroma >= minimumChroma,
                  (0.08...0.95).contains(hsl.lightness)
            else { continue }
            // Groups centred on their hue, so red is one group rather than
            // split between the two ends of the circle.
            let group = Int((hsl.hue + 0.5 / Double(hueGroups)) * Double(hueGroups)) % hueGroups
            var entry = groups[group] ?? (0, RGB(red: 0, green: 0, blue: 0), 0)
            entry.score += hsl.chroma
            entry.sum.red += pixel.red
            entry.sum.green += pixel.green
            entry.sum.blue += pixel.blue
            entry.count += 1
            groups[group] = entry
        }
        guard let best = groups.values.max(by: { $0.score < $1.score }) else { return nil }
        return RGB(
            red: best.sum.red / best.count,
            green: best.sum.green / best.count,
            blue: best.sum.blue / best.count)
    }

    /// The cover's hue, at a strength a glow behind white text can carry.
    static func glow(for colour: RGB) -> RGB {
        let hue = hsl(colour).hue
        return rgb(hue: hue, saturation: glowSaturation, lightness: glowLightness)
    }

    static let glowSaturation = 0.5
    static let glowLightness = 0.3

    /// Twelve groups: fine enough to keep red and orange apart, coarse enough
    /// that the shades of one colour count together.
    private static let hueGroups = 12
    /// Below this a pixel is grey for every purpose here.
    private static let minimumChroma = 0.12

    static func hsl(_ colour: RGB) -> (hue: Double, chroma: Double, lightness: Double) {
        let high = max(colour.red, colour.green, colour.blue)
        let low = min(colour.red, colour.green, colour.blue)
        let chroma = high - low
        let lightness = (high + low) / 2
        guard chroma > 0 else { return (0, 0, lightness) }
        let sector: Double = switch high {
        case colour.red: ((colour.green - colour.blue) / chroma).truncatingRemainder(dividingBy: 6)
        case colour.green: (colour.blue - colour.red) / chroma + 2
        default: (colour.red - colour.green) / chroma + 4
        }
        let hue = (sector < 0 ? sector + 6 : sector) / 6
        return (hue, chroma, lightness)
    }

    private static func rgb(hue: Double, saturation: Double, lightness: Double) -> RGB {
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
        return RGB(red: r + m, green: g + m, blue: b + m)
    }
}
