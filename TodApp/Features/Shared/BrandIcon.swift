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
/// - SoundCloud: the white cloud from SoundCloud's Media Kit, the colourway
///   its developer guidelines give for dark grounds (orange ground takes the
///   black one). Wherever SoundCloud's data shows it must link to the sound.
///
/// Apple's and Spotify's are vector files in the asset catalog. Their CSS
/// classes were written out as plain SVG attributes -- iOS draws no
/// `<style>` -- with the colours and shapes untouched. SoundCloud hands out
/// images only; they sit in the catalog as they came, converted to PNG.
struct BrandIcon: View {
    enum Brand { case appleMusic, spotify, soundCloud }

    let brand: Brand
    var size: CGFloat = 18

    private var asset: String {
        switch brand {
        case .appleMusic: "AppleMusicIcon"
        case .spotify: "SpotifyIconWhite"
        case .soundCloud: "SoundCloudIconWhite"
        }
    }

    private var name: String {
        switch brand {
        case .appleMusic: "Apple Music"
        case .spotify: "Spotify"
        case .soundCloud: "SoundCloud"
        }
    }

    var body: some View {
        Image(asset)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel(name)
    }
}
