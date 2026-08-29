import Foundation
import Testing
@testable import TodApp

@Suite
struct SoundCloudOEmbedTests {
    private let source = TrackSource(
        service: .soundcloud,
        serviceTrackID: "https://soundcloud.com/artist/some-track",
        pageURL: URL(string: "https://soundcloud.com/artist/some-track")!,
        artworkURL: nil
    )

    @Test
    func mapsTitleAndAuthor() throws {
        let data = Data("""
        {"title":"Some Track by Artist","author_name":"Artist",
         "thumbnail_url":"https://i1.sndcdn.com/artwork.jpg"}
        """.utf8)

        let candidate = try SoundCloudOEmbedMapper.candidate(from: data, source: source)

        #expect(candidate.title == "Some Track by Artist")
        #expect(candidate.artist == "Artist")
        #expect(candidate.source.artworkURL?.absoluteString == "https://i1.sndcdn.com/artwork.jpg")
        #expect(candidate.source.service == .soundcloud)
        #expect(candidate.source.serviceTrackID == source.serviceTrackID)
        #expect(candidate.source.pageURL == source.pageURL)
    }

    @Test
    func toleratesMissingThumbnail() throws {
        let data = Data("""
        {"title":"Some Track","author_name":"Artist"}
        """.utf8)

        let candidate = try SoundCloudOEmbedMapper.candidate(from: data, source: source)

        #expect(candidate.source.artworkURL == nil)
        #expect(candidate.source.serviceTrackID == source.serviceTrackID)
        #expect(candidate.source.pageURL == source.pageURL)
    }

    @Test
    func reportsUnavailableTrackFor404() async {
        let client = SoundCloudOEmbedClient(performRequest: { _ in
            (Data(), HTTPURLResponse(
                url: URL(string: "https://soundcloud.com/oembed")!,
                statusCode: 404, httpVersion: nil, headerFields: nil)!)
        })

        await #expect(throws: TodAppError.trackUnavailable) {
            try await client.candidate(for: source)
        }
    }

    @Test
    func reportsRateLimitedFor429() async {
        let client = SoundCloudOEmbedClient(performRequest: { _ in
            (Data(), HTTPURLResponse(
                url: URL(string: "https://soundcloud.com/oembed")!,
                statusCode: 429, httpVersion: nil, headerFields: nil)!)
        })

        await #expect(throws: TodAppError.rateLimited) {
            try await client.candidate(for: source)
        }
    }
}
