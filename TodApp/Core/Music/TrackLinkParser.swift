import Foundation

/// Turns pasted text into a TrackSource. Pure and offline: this is where bad
/// input is caught, so every odd URL shape belongs in the test table.
enum TrackLinkParser {
    static func parse(_ text: String) -> TrackSource? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let id = spotifyTrackID(from: trimmed) {
            let page = URL(string: "https://open.spotify.com/track/\(id)")!
            return TrackSource(service: .spotify, serviceTrackID: id, pageURL: page, artworkURL: nil)
        }
        if let page = soundCloudTrackURL(from: trimmed) {
            return TrackSource(
                service: .soundcloud,
                serviceTrackID: page.absoluteString,
                pageURL: page,
                artworkURL: nil
            )
        }
        return nil
    }

    private static func spotifyTrackID(from text: String) -> String? {
        if text.hasPrefix("spotify:track:") {
            let id = String(text.dropFirst("spotify:track:".count))
            return id.isEmpty ? nil : id
        }
        guard let components = URLComponents(string: text),
              components.host == "open.spotify.com" else { return nil }
        // Path is /track/<id>, optionally locale-prefixed: /intl-de/track/<id>
        let parts = components.path.split(separator: "/").map(String.init)
        guard let trackIndex = parts.firstIndex(of: "track"),
              parts.indices.contains(trackIndex + 1) else { return nil }
        return parts[trackIndex + 1]
    }

    private static func soundCloudTrackURL(from text: String) -> URL? {
        guard var components = URLComponents(string: text),
              components.host?.hasSuffix("soundcloud.com") == true else { return nil }
        let parts = components.path.split(separator: "/").map(String.init)
        // A track is /<user>/<slug>. /sets/ marks a playlist, which we reject.
        guard parts.count == 2, !parts.contains("sets") else { return nil }
        components.query = nil
        components.fragment = nil
        return components.url
    }
}
