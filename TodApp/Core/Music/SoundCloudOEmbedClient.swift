import Foundation

/// SoundCloud's oEmbed endpoint is public and needs no API key -- which matters,
/// because SoundCloud no longer grants API credentials on request.
enum SoundCloudOEmbedMapper {
    struct Response: Decodable {
        let title: String
        let author_name: String
        let thumbnail_url: String?
    }

    static func candidate(from data: Data, source: TrackSource) throws -> TrackCandidate {
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        var resolved = source
        resolved.artworkURL = decoded.thumbnail_url.flatMap { URL(string: $0) }
        return TrackCandidate(
            title: title(decoded.title, without: decoded.author_name),
            artist: decoded.author_name, source: resolved)
    }

    /// oEmbed names a track "<title> by <artist>"; the song is only the title.
    static func title(_ title: String, without artist: String) -> String {
        let suffix = " by \(artist)"
        guard !artist.isEmpty, title.hasSuffix(suffix), title.count > suffix.count else { return title }
        return String(title.dropLast(suffix.count))
    }
}

/// What SoundCloud's public track page says that oEmbed does not: the length,
/// and the title without the artist appended.
enum SoundCloudTrackPage {
    struct Details: Equatable {
        var title: String?
        var durationSeconds: Int?
    }

    static func details(from html: String) -> Details {
        Details(
            title: meta(#"property="og:title""#, in: html).flatMap { $0.isEmpty ? nil : $0 },
            durationSeconds: meta(#"itemprop="duration""#, in: html).flatMap(seconds(isoDuration:)))
    }

    /// `PT00H03M33S` -> 213.
    static func seconds(isoDuration text: String) -> Int? {
        guard let match = text.firstMatch(of: /^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$/) else { return nil }
        let hours = match.1.flatMap { Int($0) } ?? 0
        let minutes = match.2.flatMap { Int($0) } ?? 0
        let secs = match.3.flatMap { Int($0) } ?? 0
        let total = hours * 3600 + minutes * 60 + secs
        return total > 0 ? total : nil
    }

    private static func meta(_ attribute: String, in html: String) -> String? {
        // The attribute as a lookahead: attributes come in any order.
        let pattern = #"<meta(?=[^>]*\#(attribute))[^>]*\bcontent="([^"]*)""#
        guard let match = html.firstMatch(of: try! Regex(pattern)),
              let content = match.output[1].substring
        else { return nil }
        return String(content)
    }
}

struct SoundCloudOEmbedClient: Sendable {
    typealias PerformRequest = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let performRequest: PerformRequest

    init(performRequest: @escaping PerformRequest = { try await URLSession.shared.data(for: $0) }) {
        self.performRequest = performRequest
    }

    func candidate(for source: TrackSource) async throws -> TrackCandidate {
        var components = URLComponents(string: "https://soundcloud.com/oembed")!
        components.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "url", value: source.pageURL.absoluteString)
        ]
        let (data, response) = try await performRequest(URLRequest(url: components.url!))
        guard let http = response as? HTTPURLResponse else {
            throw TodAppError.trackUnavailable
        }
        var candidate: TrackCandidate
        switch http.statusCode {
        case 200:
            candidate = try SoundCloudOEmbedMapper.candidate(from: data, source: source)
        case 429:
            throw TodAppError.rateLimited
        default:
            throw TodAppError.trackUnavailable
        }
        // The length (and a clean title) from the public page. Nothing, not an
        // error, when it fails: oEmbed has already answered.
        if let (page, pageResponse) = try? await performRequest(URLRequest(url: source.pageURL)),
           (pageResponse as? HTTPURLResponse)?.statusCode == 200 {
            let details = SoundCloudTrackPage.details(from: String(decoding: page, as: UTF8.self))
            if let title = details.title { candidate.title = title }
            candidate.durationSeconds = details.durationSeconds
        }
        return candidate
    }

    /// Where a share link (`on.soundcloud.com/…`) leads: the request follows
    /// the redirect, and the address it ends at is the track's.
    func resolve(shareLink: URL) async throws -> URL {
        let (_, response) = try await performRequest(URLRequest(url: shareLink))
        guard let url = response.url, url.host?.lowercased() != "on.soundcloud.com" else {
            throw TodAppError.trackUnavailable
        }
        return url
    }
}
