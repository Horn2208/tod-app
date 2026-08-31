import Foundation

/// Turns pasted text into a TrackSource. Pure and offline: this is where bad
/// input is caught, so every odd URL shape belongs in the test table.
enum TrackLinkParser {
    static func parse(_ text: String) -> TrackSource? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let id = spotifyTrackID(from: trimmed) {
            guard let page = URL(string: "https://open.spotify.com/track/\(id)") else { return nil }
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
        var id: String?

        if text.hasPrefix("spotify:track:") {
            id = String(text.dropFirst("spotify:track:".count))
            guard let id = id, !id.isEmpty else { return nil }
        } else {
            guard let components = URLComponents(string: text),
                  components.scheme == "http" || components.scheme == "https",
                  components.host == "open.spotify.com" else { return nil }
            // Path is /track/<id>, optionally locale-prefixed: /intl-de/track/<id>
            let parts = components.path.split(separator: "/").map(String.init)
            guard let trackIndex = parts.firstIndex(of: "track"),
                  parts.indices.contains(trackIndex + 1) else { return nil }
            id = parts[trackIndex + 1]
        }

        // Validate: Spotify track IDs should only contain alphanumeric characters
        guard let validID = id, validID.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        return validID
    }

    private static func soundCloudTrackURL(from text: String) -> URL? {
        guard var components = URLComponents(string: text),
              components.scheme == "http" || components.scheme == "https",
              components.host == "soundcloud.com" || components.host?.hasSuffix(".soundcloud.com") == true else { return nil }
        let parts = components.path.split(separator: "/").map(String.init)
        // A track is /<user>/<slug>. /sets/ marks a playlist, which we reject.
        guard parts.count == 2, !parts.contains("sets") else { return nil }
        components.query = nil
        components.fragment = nil
        return components.url
    }
}
