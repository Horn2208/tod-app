import Foundation
import Testing
@testable import TodApp

@Suite
struct SpotifyResponseMapperTests {
    /// Trimmed copy of a real /v1/search?type=track response.
    private let recorded = Data("""
    {"tracks":{"items":[
      {"id":"4cOdK2wGLETKBW3PvgPWqT","name":"As It Was",
       "artists":[{"name":"Harry Styles"}],
       "external_urls":{"spotify":"https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT"},
       "album":{"images":[
         {"url":"https://i.scdn.co/image/large","width":640},
         {"url":"https://i.scdn.co/image/small","width":64}]}},
      {"id":"7ouMYWpwJ422jRcDASZB7P","name":"One More Time",
       "artists":[{"name":"Daft Punk"},{"name":"Romanthony"}],
       "external_urls":{"spotify":"https://open.spotify.com/track/7ouMYWpwJ422jRcDASZB7P"},
       "album":{"images":[]}}
    ]}}
    """.utf8)

    @Test
    func mapsTracksToCandidates() throws {
        let candidates = try SpotifyResponseMapper.candidates(from: recorded)

        #expect(candidates.count == 2)
        #expect(candidates[0].title == "As It Was")
        #expect(candidates[0].artist == "Harry Styles")
        #expect(candidates[0].source.service == .spotify)
        #expect(candidates[0].source.serviceTrackID == "4cOdK2wGLETKBW3PvgPWqT")
    }

    @Test
    func joinsMultipleArtists() throws {
        let candidates = try SpotifyResponseMapper.candidates(from: recorded)
        #expect(candidates[1].artist == "Daft Punk, Romanthony")
    }

    @Test
    func picksTheSmallestArtworkAndToleratesNone() throws {
        let candidates = try SpotifyResponseMapper.candidates(from: recorded)
        #expect(candidates[0].source.artworkURL?.absoluteString == "https://i.scdn.co/image/small")
        #expect(candidates[1].source.artworkURL == nil)
    }
}

@Suite
struct MusicSearchRepositoryContractTests {
    @Test
    func blankQueryReturnsNoResultsWithoutHittingTheNetwork() async throws {
        let repo = SpotifySearchRepository(
            tokenProvider: SpotifyTokenProvider(
                credentials: SpotifyCredentials(clientID: "id", clientSecret: "s"),
                fetch: { _ in Issue.record("must not fetch a token"); return ("x", 1) }
            ),
            performRequest: { _ in
                Issue.record("must not hit the network for a blank query")
                return (Data(), HTTPURLResponse())
            }
        )

        let results = try await repo.searchTracks(matching: "   ")

        #expect(results.isEmpty)
    }
}
