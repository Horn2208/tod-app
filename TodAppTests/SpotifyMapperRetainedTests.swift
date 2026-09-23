import Foundation
import Testing
@testable import TodApp

/// The search body is unchanged by signing in; only the token in front of it
/// changed. This is the piece of the old client-credentials path that stays.
@Suite
struct SpotifyMapperRetainedTests {
    @Test
    func stillMapsASearchBodyToCandidates() throws {
        let body = Data(#"""
        {"tracks":{"items":[
          {"id":"4cOdK2wGLETKBW3PvgPWqT","name":"As It Was","duration_ms":167000,
           "artists":[{"name":"Harry Styles"}],
           "external_urls":{"spotify":"https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT"},
           "album":{"images":[
             {"url":"https://i.scdn.co/image/large","width":640},
             {"url":"https://i.scdn.co/image/medium","width":300},
             {"url":"https://i.scdn.co/image/small","width":64}]}}
        ]}}
        """#.utf8)

        let candidates = try SpotifyResponseMapper.candidates(from: body)

        #expect(candidates.count == 1)
        #expect(candidates[0].title == "As It Was")
        #expect(candidates[0].durationSeconds == 167)
        #expect(candidates[0].source?.artworkURL?.absoluteString == "https://i.scdn.co/image/medium")
    }
}
