import SwiftUI

/// Hex values verified directly against `tod-prototype.html` `:root` block.
/// See docs/superpowers/specs/brand-spec.md.
extension Color {
    static let todBackground = Color(hex: "#121014")
    static let todSurface = Color(hex: "#1c1a20")
    static let todSurface2 = Color(hex: "#262129")
    static let todSurface3 = Color(hex: "#302a33")
    static let todLine = Color(hex: "#37313b")
    static let todText = Color(hex: "#f4efe6")
    static let todTextDim = Color(hex: "#a99fac")
    static let todTextFaint = Color(hex: "#6f6672")
    static let todAccent = Color(hex: "#b3527a")
    static let todAccent2 = Color(hex: "#e0b64a")
    /// The far end of the accent gradient (pink to lilac).
    static let todLilac = Color(hex: "#a58bd9")
    static let todGood = Color(hex: "#5ad1a0")

    /// The daily streak, and nothing else. Gold reads as an award and pink is
    /// the brand accent -- a run of days needs its own fire, or it borrows a
    /// meaning that belongs to something else.
    static let todStreak = Color(hex: "#ff7a45")

    init(hex: String) {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        sanitized.removeAll { $0 == "#" }
        var value: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&value)

        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
