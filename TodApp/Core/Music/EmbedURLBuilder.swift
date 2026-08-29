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
            return URL(string: "https://open.spotify.com/embed/track/\(source.serviceTrackID)?theme=0")!
        case .soundcloud:
            var components = URLComponents(string: "https://w.soundcloud.com/player/")!
            components.queryItems = [
                URLQueryItem(name: "url", value: source.pageURL.absoluteString),
                URLQueryItem(name: "color", value: accentHex),
                URLQueryItem(name: "visual", value: "false"),
                URLQueryItem(name: "hide_related", value: "true")
            ]
            return components.url!
        }
    }
}
