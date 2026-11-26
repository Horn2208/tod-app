import Foundation

/// The hits on SoundCloud's search page. SoundCloud grants no new API keys
/// (its paid Artist Pro route aside, not taken for now), but the page lists
/// its results in plain HTML for browsers without JavaScript -- a path and a
/// title per track. Like `SoundCloudTrackPage`, this reads a public page and
/// may need a look should SoundCloud change its markup.
enum SoundCloudSearchPage {
    struct Hit: Equatable {
        let pageURL: URL
        let title: String
    }

    static func hits(in html: String) -> [Hit] {
        let pattern = /<li><h2><a href="(\/[^"\/]+\/[^"\/?]+)">([^<]*)<\/a><\/h2><\/li>/
        return html.matches(of: pattern).compactMap { match in
            let path = String(match.1)
            guard !path.contains("/sets/"), let url = URL(string: "https://soundcloud.com\(path)") else { return nil }
            return Hit(pageURL: url, title: SpotifyTrackPage.decodeEntities(String(match.2)))
        }
    }
}

/// SoundCloud search for the post sheet: the search page's hits, each filled
/// in with its artist, cover and length through `SoundCloudOEmbedClient`.
struct SoundCloudSearchClient: Sendable {
    typealias PerformRequest = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    /// Hits looked up; the page lists more, but each costs a request or two.
    static let limit = 8

    private let performRequest: PerformRequest

    init(performRequest: @escaping PerformRequest = { try await URLSession.shared.data(for: $0) }) {
        self.performRequest = performRequest
    }

    func search(_ term: String) async throws -> [TrackCandidate] {
        var components = URLComponents(string: "https://soundcloud.com/search/sounds")!
        components.queryItems = [URLQueryItem(name: "q", value: term)]
        let (data, response) = try await performRequest(URLRequest(url: components.url!))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw TodAppError.searchUnavailable }
        let hits = Array(SoundCloudSearchPage.hits(in: String(decoding: data, as: UTF8.self)).prefix(Self.limit))

        let lookup = SoundCloudOEmbedClient(performRequest: performRequest)
        return await withTaskGroup(of: (Int, TrackCandidate).self) { group in
            for (index, hit) in hits.enumerated() {
                group.addTask {
                    guard let source = TrackLinkParser.parse(hit.pageURL.absoluteString) else {
                        return (index, TrackCandidate(title: hit.title, artist: "", source: nil))
                    }
                    // A track that cannot be looked up is still offered, under
                    // the title the list gave it.
                    let found = try? await lookup.candidate(for: source)
                    return (index, found ?? TrackCandidate(title: hit.title, artist: "", source: source))
                }
            }
            var filled: [(Int, TrackCandidate)] = []
            for await result in group { filled.append(result) }
            return filled.sorted { $0.0 < $1.0 }.map(\.1).filter { $0.source != nil }
        }
    }
}
