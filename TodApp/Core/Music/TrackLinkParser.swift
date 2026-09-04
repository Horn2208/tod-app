import Foundation

/// Turns pasted text into a TrackSource. Pure and offline: this is where bad
/// input is caught, so every odd URL shape belongs in the test table.
enum TrackLinkParser {
    /// Spotify IDs are base62. `Character.isLetter` and `.isNumber` are much
    /// wider -- they accept umlauts, CJK and Arabic-Indic digits -- so the check
    /// spells the alphabet out instead of asking whether something is "a letter".
    private static let base62 = Set(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    )

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
                  let scheme = components.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  components.host?.lowercased() == "open.spotify.com" else { return nil }
            // Path is /track/<id>, optionally locale-prefixed: /intl-de/track/<id>
            let parts = components.path.split(separator: "/").map(String.init)
            guard let trackIndex = parts.firstIndex(of: "track"),
                  parts.indices.contains(trackIndex + 1) else { return nil }
            id = parts[trackIndex + 1]
        }

        guard let validID = id, !validID.isEmpty, validID.allSatisfy(base62.contains) else {
            return nil
        }
        return validID
    }

    private static func soundCloudTrackURL(from text: String) -> URL? {
        guard var components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host?.lowercased(),
              host == "soundcloud.com" || host.hasSuffix(".soundcloud.com") else { return nil }
        let parts = components.path.split(separator: "/").map(String.init)
        // A track is /<user>/<slug>. /sets/ marks a playlist, which we reject.
        guard parts.count == 2, !parts.contains("sets") else { return nil }
        components.query = nil
        components.fragment = nil
        // Credentials in the authority go the same way as the query and the
        // fragment. Every later use hands `pageURL` to somebody else -- the
        // oEmbed lookup puts it in a query string sent to soundcloud.com, the
        // widget URL puts it in a page WebKit loads -- and none of them needs
        // whatever was sitting before the `@`.
        components.user = nil
        components.password = nil
        // Scheme and host are case-insensitive, so they are compared folded
        // above and stored folded here: one track then has one `serviceTrackID`
        // instead of one per capitalisation somebody happened to paste.
        components.host = host
        // Pasting an http link is ordinary; carrying that scheme forward would
        // mean the app later fetches the page in the clear. Spotify links get
        // this for free because their URL is rebuilt from the ID.
        components.scheme = "https"
        return components.url
    }
}
