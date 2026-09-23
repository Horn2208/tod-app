import Foundation

/// Spotify's oEmbed endpoint is public and needs no client credentials or
/// access token -- unlike search, which goes through SpotifySearchRepository
/// and the token provider. Used only to resolve display metadata for a
/// pasted link, never to search.
enum SpotifyOEmbedMapper {
    struct Response: Decodable {
        let title: String
        let thumbnail_url: String?
    }

    static func candidate(from data: Data, source: TrackSource) throws -> TrackCandidate {
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        var resolved = source
        resolved.artworkURL = decoded.thumbnail_url.flatMap { URL(string: $0) }
        // Spotify's oEmbed response has no author_name field, unlike
        // SoundCloud's. Put the whole title in `title` and leave `artist`
        // empty rather than guessing a split out of the title string.
        return TrackCandidate(title: decoded.title, artist: "", source: resolved)
    }
}

struct SpotifyOEmbedClient: Sendable {
    typealias PerformRequest = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let performRequest: PerformRequest

    init(performRequest: @escaping PerformRequest = { try await URLSession.shared.data(for: $0) }) {
        self.performRequest = performRequest
    }

    func candidate(for source: TrackSource) async throws -> TrackCandidate {
        var components = URLComponents(string: "https://open.spotify.com/oembed")!
        components.queryItems = [
            URLQueryItem(name: "url", value: source.pageURL.absoluteString)
        ]
        let (data, response) = try await performRequest(URLRequest(url: components.url!))
        guard let http = response as? HTTPURLResponse else {
            throw TodAppError.trackUnavailable
        }
        var candidate: TrackCandidate
        switch http.statusCode {
        case 200:
            candidate = try SpotifyOEmbedMapper.candidate(from: data, source: source)
        case 429:
            throw TodAppError.rateLimited
        default:
            throw TodAppError.trackUnavailable
        }
        // The artist and the length, which oEmbed leaves out, from the public
        // track page. Without the artist Apple's catalog could not find the
        // song, so a pasted link never played Apple's preview or whole song.
        let details = await pageDetails(for: source)
        if let artist = details.artist { candidate.artist = artist }
        candidate.durationSeconds = details.durationSeconds
        return candidate
    }

    /// Nothing, rather than an error, when the page fails: the link resolved
    /// through oEmbed already and posts as it did before.
    private func pageDetails(for source: TrackSource) async -> SpotifyTrackPage.Details {
        guard let (data, response) = try? await performRequest(URLRequest(url: source.pageURL)),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return SpotifyTrackPage.Details() }
        return SpotifyTrackPage.details(from: String(decoding: data, as: UTF8.self))
    }
}

/// What Spotify's public track page says in its meta tags: the artists, as
/// Spotify lists them, and the length in seconds. Public like oEmbed, no token.
enum SpotifyTrackPage {
    struct Details: Equatable {
        var artist: String?
        var durationSeconds: Int?
    }

    static func details(from html: String) -> Details {
        let artist = meta("music:musician_description", in: html).flatMap { $0.isEmpty ? nil : $0 }
        let duration = meta("music:duration", in: html).flatMap { Int($0) }.flatMap { $0 > 0 ? $0 : nil }
        return Details(artist: artist, durationSeconds: duration)
    }

    private static func meta(_ name: String, in html: String) -> String? {
        // The name as a lookahead: attributes come in any order.
        let pattern = #"<meta(?=[^>]*\b(?:name|property)="\#(name)")[^>]*\bcontent="([^"]*)""#
        guard let match = html.firstMatch(of: try! Regex(pattern)),
              let content = match.output[1].substring
        else { return nil }
        return decodeEntities(String(content))
    }

    /// The escapes an HTML attribute uses: named ones for the usual five, and
    /// numeric ones, decimal or hex, for everything else.
    private static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        let named = ["amp": "&", "quot": "\"", "apos": "'", "lt": "<", "gt": ">"]
        var result = ""
        var rest = Substring(text)
        while let amp = rest.firstIndex(of: "&") {
            result += rest[..<amp]
            let after = rest[rest.index(after: amp)...]
            guard let semicolon = after.firstIndex(of: ";"), after.distance(from: after.startIndex, to: semicolon) <= 8 else {
                result += "&"
                rest = after
                continue
            }
            let entity = after[..<semicolon]
            var decoded: String?
            if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
                decoded = UInt32(entity.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String($0) }
            } else if entity.hasPrefix("#") {
                decoded = UInt32(entity.dropFirst()).flatMap(Unicode.Scalar.init).map { String($0) }
            } else {
                decoded = named[String(entity)]
            }
            if let decoded {
                result += decoded
                rest = after[after.index(after: semicolon)...]
            } else {
                result += "&"
                rest = after
            }
        }
        return result + rest
    }
}
