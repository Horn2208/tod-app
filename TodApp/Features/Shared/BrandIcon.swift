import SwiftUI

/// The services' own icons, exactly as they hand them out -- never redrawn,
/// recoloured, cropped or turned.
///
/// - Apple Music: the colour icon from Apple's Apple Music Identity
///   Guidelines, allowed "to link to music content within apps, where the
///   Apple Music badge does not fit". Apple's logo alone is not allowed.
/// - Spotify: the icon from Spotify's Design & Branding Guidelines, in white:
///   green is for pure black or white grounds only, and this app's are dark
///   but neither. Never smaller than 21 pixels, and kept clear by half its
///   height on every side.
///
/// Both are vector files in the asset catalog. Their CSS classes were written
/// out as plain SVG attributes -- iOS draws no `<style>` -- with the colours
/// and shapes untouched.
struct BrandIcon: View {
    enum Brand { case appleMusic, spotify }

    let brand: Brand
    var size: CGFloat = 18

    var body: some View {
        Image(brand == .appleMusic ? "AppleMusicIcon" : "SpotifyIconWhite")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel(brand == .appleMusic ? "Apple Music" : "Spotify")
    }
}
