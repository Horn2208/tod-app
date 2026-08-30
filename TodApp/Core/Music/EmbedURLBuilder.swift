import Foundation

/// Builds the official embed-player URL for a track. Kept separate from the
/// WKWebView wrapper so the URL shape is testable without a web view.
enum EmbedURLBuilder {
    /// Matches Color.todAccent. Hard-coded because SoundCloud wants a hex string,
    /// not a SwiftUI Color.
    private static let accentHex = "#b3527a"

    static func embedURL(for source: TrackSource) -> URL {
        switch source.service {
        case .spotify:
            // theme=0 is the dark player.
            // Use URLComponents to properly percent-encode the track ID, preventing
            // injection of special characters like ? or # into the URL structure.
            var components = URLComponents()
            components.scheme = "https"
            components.host = "open.spotify.com"

            // Percent-encode the track ID to prevent URL corruption
            let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
            let encodedID = source.serviceTrackID.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? source.serviceTrackID

            components.path = "/embed/track/\(encodedID)"
            components.queryItems = [URLQueryItem(name: "theme", value: "0")]
            return components.url!
        case .soundcloud:
            var components = URLComponents(string: "https://w.soundcloud.com/player/")!
            // The widget's `url` is itself a URL, so encode it once for the
            // enclosing query. URLQueryItem would encode any existing percent
            // escapes a second time (`%20` -> `%2520`), which makes SoundCloud
            // try to resolve a different, invalid permalink.
            let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
            let permalink = source.pageURL.absoluteString.removingPercentEncoding ?? source.pageURL.absoluteString
            let encodedPermalink = permalink.addingPercentEncoding(withAllowedCharacters: allowedCharacters)!
            let encodedAccent = accentHex.addingPercentEncoding(withAllowedCharacters: allowedCharacters)!
            components.percentEncodedQuery = "url=\(encodedPermalink)&color=\(encodedAccent)&visual=false&hide_related=true"
            return components.url!
        }
    }
}
