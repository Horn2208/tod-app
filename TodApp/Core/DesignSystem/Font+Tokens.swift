import SwiftUI

/// Font roles from tod-prototype.html: Unbounded (display), Manrope (body), JetBrains Mono (meta).
/// Falls back to system fonts until the .ttf files in Resources/Fonts are bundled and
/// registered in Info.plist's UIAppFonts.
extension Font {
    static func todDisplay(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .custom("Unbounded", size: size, relativeTo: .headline).weight(weight)
    }

    static func todBody(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Manrope", size: size, relativeTo: .body).weight(weight)
    }

    static func todMono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .custom("JetBrains Mono", size: size, relativeTo: .caption).weight(weight)
    }
}
