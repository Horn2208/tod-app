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

    /// Apple's New York in italic, for the few words that should read like a
    /// title on a record sleeve: song titles and headlines. A system face, so
    /// no file is bundled. Fixed size, like a cover's own lettering.
    static func todSerif(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif).italic()
    }

    /// The same face, following Dynamic Type through a text style.
    static func todSerif(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .serif, weight: weight).italic()
    }
}

extension View {
    /// A soft light around text: a tight shadow for the edge, a wide one for
    /// the halo, both in one colour. Sparingly -- like the streak's sheen, it
    /// means something only while it is rare.
    func todGlow(color: Color = .todAccent) -> some View {
        shadow(color: color.opacity(0.9), radius: 2)
            .shadow(color: color.opacity(0.55), radius: 12)
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
