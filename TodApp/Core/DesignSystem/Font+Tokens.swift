import SwiftUI

/// Font roles from tod-prototype.html: Unbounded (display), Manrope (body),
/// JetBrains Mono (meta). The files are in Resources/Fonts and listed under
/// `UIAppFonts`: static weights, each with its own PostScript name, so a weight
/// is picked by name (`BrandFont`) rather than left to the system's matching --
/// a name that does not resolve falls back to the system font without a word.
extension Font {
    static func todDisplay(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .custom(BrandFont.display(weight), size: size, relativeTo: .headline)
    }

    static func todBody(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(BrandFont.body(weight), size: size, relativeTo: .body)
    }

    static func todMono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .custom(BrandFont.mono(weight), size: size, relativeTo: .caption)
    }
}

/// Which bundled face a weight asks for. Pure, so a test can check every
/// name resolves (`BrandFontTests`).
enum BrandFont {
    /// Unbounded is bundled in bold only: the headlines are all bold.
    static func display(_ weight: Font.Weight) -> String {
        "Unbounded-Bold"
    }

    static func body(_ weight: Font.Weight) -> String {
        "Manrope-\(style(weight))"
    }

    static func mono(_ weight: Font.Weight) -> String {
        "JetBrainsMono-\(style(weight))"
    }

    /// The nearest of the four bundled weights.
    static func style(_ weight: Font.Weight) -> String {
        switch weight {
        case .medium: "Medium"
        case .semibold: "SemiBold"
        case .bold, .heavy, .black: "Bold"
        default: "Regular"
        }
    }

    /// Every face the app asks for, for the test that each one is there.
    static var allNames: [String] {
        let weights: [Font.Weight] = [.regular, .medium, .semibold, .bold]
        return [display(.bold)] + weights.map(body) + weights.map(mono)
    }
}
