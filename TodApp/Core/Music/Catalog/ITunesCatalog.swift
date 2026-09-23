import Foundation

/// The iTunes Store's catalog through the open Search API: no key, no
/// account, no login. It knows what is *sold*, which is not quite what Apple
/// Music *streams* -- Frank Ocean's "Blonde" is missing -- and it has no ISRC
/// lookup. Both go away with MusicKit; until then, this is the catalog.
struct ITunesCatalog: MusicCatalog {
    /// Two-letter storefront. Prices and availability differ by country, and
    /// so does whether a song is there at all.
    var country: String
    var fetch: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    /// Seconds. A catalog slower than this counts as no answer, and the
    /// player falls back to Spotify's embed -- URLSession's own default is a
    /// minute, which is a minute of "Player lädt".
    static let timeout: TimeInterval = 5

    init(
        country: String = Locale.current.region?.identifier.lowercased() ?? "de",
        fetch: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = {
            try await URLSession.shared.data(for: $0)
        }
    ) {
        self.country = country
        self.fetch = fetch
    }

    func search(title: String, artist: String) async throws -> [CatalogSong] {
        try await search(term: "\(title) \(artist)")
    }

    /// Songs for whatever someone typed -- the post sheet's search when no
    /// Spotify account is connected.
    func search(term: String) async throws -> [CatalogSong] {
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "entity", value: "song"),
            // Room for the album, single and deluxe versions of one song, which
            // otherwise crowd the right one out.
            URLQueryItem(name: "limit", value: "25"),
            URLQueryItem(name: "country", value: country),
        ]
        return try await songs(from: components.url!)
    }

    func song(id: String) async throws -> CatalogSong? {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        components.queryItems = [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "country", value: country),
        ]
        return try await songs(from: components.url!).first
    }

    private func songs(from url: URL) async throws -> [CatalogSong] {
        var request = URLRequest(url: url)
        request.timeoutInterval = Self.timeout
        let (data, response) = try await fetch(request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw TodAppError.searchUnavailable
        }
        return try JSONDecoder().decode(Response.self, from: data).results.compactMap(\.song)
    }

    private struct Response: Decodable {
        let results: [Result]
    }

    private struct Result: Decodable {
        let kind: String?
        let trackId: Int?
        let trackName: String?
        let artistName: String?
        let trackTimeMillis: Int?
        let previewUrl: String?
        let trackViewUrl: String?
        let artworkUrl100: String?

        /// Songs only -- a lookup can answer with an album or a video too.
        var song: CatalogSong? {
            guard kind == "song", let trackId, let trackName, let artistName else { return nil }
            return CatalogSong(
                id: String(trackId),
                title: trackName,
                artist: artistName,
                durationSeconds: trackTimeMillis.map { $0 / 1000 },
                previewURL: previewUrl.flatMap(URL.init(string:)),
                pageURL: trackViewUrl.flatMap(URL.init(string:)),
                artworkURL: artworkUrl100.flatMap(URL.init(string:))
            )
        }
    }
}
