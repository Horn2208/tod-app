import Foundation
import Testing
@testable import TodApp

@Suite
struct SpotifyOEmbedTests {
    private let source = TrackSource(
        service: .spotify,
        serviceTrackID: "abc123",
        pageURL: URL(string: "https://open.spotify.com/track/abc123")!,
        artworkURL: nil
    )

    @Test
    func mapsTitleAndLeavesArtistEmpty() throws {
        let data = Data("""
        {"title":"Genesis - Justice","thumbnail_url":"https://i.scdn.co/image/abc.jpg"}
        """.utf8)

        let candidate = try SpotifyOEmbedMapper.candidate(from: data, source: source)

        #expect(candidate.title == "Genesis - Justice")
        #expect(candidate.artist == "")
        #expect(candidate.source.artworkURL?.absoluteString == "https://i.scdn.co/image/abc.jpg")
        #expect(candidate.source.service == .spotify)
        #expect(candidate.source.serviceTrackID == source.serviceTrackID)
        #expect(candidate.source.pageURL == source.pageURL)
    }

    @Test
    func toleratesMissingThumbnail() throws {
        let data = Data("""
        {"title":"Genesis - Justice"}
        """.utf8)

        let candidate = try SpotifyOEmbedMapper.candidate(from: data, source: source)

        #expect(candidate.source.artworkURL == nil)
        #expect(candidate.source.serviceTrackID == source.serviceTrackID)
        #expect(candidate.source.pageURL == source.pageURL)
    }

    @Test
    func reportsUnavailableTrackFor404() async {
        let client = SpotifyOEmbedClient(performRequest: { _ in
            (Data(), HTTPURLResponse(
                url: URL(string: "https://open.spotify.com/oembed")!,
                statusCode: 404, httpVersion: nil, headerFields: nil)!)
        })

        await #expect(throws: TodAppError.trackUnavailable) {
            try await client.candidate(for: source)
        }
    }

    @Test
    func reportsRateLimitedFor429() async {
        let client = SpotifyOEmbedClient(performRequest: { _ in
            (Data(), HTTPURLResponse(
                url: URL(string: "https://open.spotify.com/oembed")!,
                statusCode: 429, httpVersion: nil, headerFields: nil)!)
        })

        await #expect(throws: TodAppError.rateLimited) {
            try await client.candidate(for: source)
        }
    }
}
